import CoreLocation
import SQLite
import Foundation
import AsyncLocationKit


struct Stop {
    let stopID: String
    let stopName: String
    var platformIDs: [String]
    var distanceMiles: Double?
}


class TransitDataFetcher: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var departuresMinutes: [String: [Int]] = [:]
    @Published var closestStop: Stop = sampleStop
    @Published var lastUpdated: Date?
    
    let gtfsrtUrlString = "https://api.bart.gov/gtfsrt/tripupdate.aspx"
    var feedMessage: TransitRealtime_FeedMessage?
    var locationManager = AsyncLocationManager(desiredAccuracy: .hundredMetersAccuracy)
    var userLocation: CLLocation = CLLocation(latitude: 37.764831501887876, longitude: -122.42142043985223)
    var gtfsDb: Connection?
    
    override init() {
        super.init()
        Task {
            let permission = await locationManager.requestPermission(with: .whenInUsage)
            if permission != .authorizedWhenInUse {
                print("not authorized")
            }
        }
        do {
            gtfsDb = try Connection(GTFS_DB_URL, readonly: true)
        } catch {
            print("Not able to connect to DB")
        }
    }
    
    enum FetchError: Error {
        case badRequest
        case badJSON
    }
    
    func fetchData() async
    throws  {
        guard let url = URL(string: gtfsrtUrlString) else { return }
        
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FetchError.badRequest }
        let permission = await locationManager.requestPermission(with: .whenInUsage)
        if permission != .authorizedWhenInUse {
            print("not permitted")
        }
        let locationUpdate = try await locationManager.requestLocation()
        
        Task { @MainActor in
            let now = Date()
            feedMessage = try TransitRealtime_FeedMessage(serializedData: data)
            switch locationUpdate {
                case .didUpdateLocations(let locations):
                    userLocation = locations.last!
                case .didPaused, .didResume, .none, .didFailWith:
                    print("no location update")
            }
            
            // Find the closest station to the user.
            self.closestStop = getClosestStopSQL(location: userLocation, db: gtfsDb!)!
            
            // Figure out the scheduled departures for that station.
            let activeServiceIDs = getActiveServices(date: now, db: self.gtfsDb!)
            let departures = getScheduledDepartures(stop: self.closestStop, serviceIDs: activeServiceIDs, date: now, db: self.gtfsDb!)
            
            // Update with realtime trip data
            var updatedDepartureDates: [String: Date]?
            if feedMessage != nil {
                updatedDepartureDates = updateDepartures(stop: self.closestStop, feedMessage: self.feedMessage!, departures: departures)
            } else {
                updatedDepartureDates = departures
            }
            
            // Convert from dates to the next few departure times in relative minutes, by route.
            let routeDepartures = getRouteDepartures(departures: updatedDepartureDates!, db: self.gtfsDb!)
            
            // Get the next three trains for each route.
            self.departuresMinutes = nextThreeDepartures(departures: routeDepartures)
            
            lastUpdated = now
        }
    }
}
