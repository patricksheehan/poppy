import CoreLocation
import SQLite3
import SQLite
import Foundation

struct StopArrivals {
    let stopName: String
    var routes: [RouteArrivals]
}

struct RouteArrivals: Identifiable {
    let id = UUID()
    let routeName: String
    var arrivalMinutes: [Int]
}

let GTFS_DB_URL = Bundle.main.path(forResource: "gtfs", ofType: "db")!



class TransitDataFetcher: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var departuresMinutes: [String: [Int]] = [:]
    @Published var closestStop: Stop = Stop(stopID: "Fake", stopName: "Loading", platformIDs: ["Fake"])
    @Published var lastUpdated: String?
    
    let gtfsrtUrlString = "https://api.bart.gov/gtfsrt/tripupdate.aspx"
    var feedMessage: TransitRealtime_FeedMessage?
    var locationManager = CLLocationManager()
    var userLocation: CLLocation = CLLocation(latitude: 37.764831501887876, longitude: -122.42142043985223)
    var gtfsDb: Connection?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
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
        
        Task { @MainActor in
            feedMessage = try TransitRealtime_FeedMessage(serializedData: data)
            calculateDepartures()
        }
    }
    
    func calculateDepartures() {
        let now = Date()
        var updatedDepartures: [String: Date]?
        
        // Find the closest station to the user.
        locationManager.requestLocation()
        closestStop = getClosestStopSQL(location: userLocation, db: gtfsDb!)!
        
        // Figure out the scheduled departures for that station.
        let activeServiceIDs = getActiveServices(date: now, db: gtfsDb!)
        let departures = getScheduledDepartures(stop: closestStop, serviceIDs: activeServiceIDs, date: now, db: gtfsDb!)
        
        if feedMessage != nil {
            updatedDepartures = updateDepartures(stop: closestStop, feedMessage: feedMessage!, departures: departures)
        } else {
            updatedDepartures = departures
        }
        
        // Convert from dates to the next few departure times in relative minutes, by route.
        let routeDepartures = getRouteDepartures(departures: updatedDepartures!, db: gtfsDb!)
        let nextThreeDepartures = routeDepartures.mapValues { dates in
            return dates.sorted(by: <).prefix(3)
        }
        departuresMinutes = nextThreeDepartures.mapValues { dates in
            return dates.map { date in
                let minutesUntilDate = Int(date.timeIntervalSinceNow / 60)
                return minutesUntilDate
            }
        }
        departuresMinutes = departuresMinutes.mapValues { minutes in
            return minutes.filter { minute in
                return minute <= 120
            }
        }
        departuresMinutes = departuresMinutes.filter { route, departures in
            return !departures.isEmpty
        }
        
        // Publish an update time so users know how recent the times are.
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        dateFormatter.doesRelativeDateFormatting = true
        lastUpdated = dateFormatter.string(from: now)
    }
    
    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        calculateDepartures()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        if let location = locations.last {
            userLocation = location
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("Failed to get user location")
        print(error)
    }
    
}


func getNoonMinusTwelveHours(date: Date) -> Date {
    let calendar = Calendar.current
    let timeZone = calendar.timeZone
    let localDate = calendar.date(from: calendar.dateComponents(in: timeZone, from: date))!
    let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: localDate)!
    let noonMinus12Hours = calendar.date(byAdding: .hour, value: -12, to: noon)!
    return noonMinus12Hours
}


func dateToGTFSTimestamp(date: Date) -> Int {
    // GTFS timestamps are calculated relative to "noon minus twelve hours" on the service date.
    let noonMinus12Hours = getNoonMinusTwelveHours(date: date)
    let interval = date.timeIntervalSince(noonMinus12Hours)
    return Int(interval)
}


func gtfsTimestampToDate(serviceDate: Date, gtfsTimestamp: Int) -> Date {
    // Given a service date and a GTFS timestamp calcualtes the real timestamp.
    let calendar = Calendar.current
    let noonMinus12Hours = getNoonMinusTwelveHours(date: serviceDate)
    let timestamp = calendar.date(byAdding: .second, value: gtfsTimestamp, to: noonMinus12Hours)!
    
    return timestamp
}


func getScheduledDepartures(stop: Stop, serviceIDs: [String], date: Date, db: Connection) -> [String: Date] {
    var tripDepartures: [String: Date] = [:]
    do {
        // Get the current timestamp relative to the service day.
        let currentGTFSTimestamp = dateToGTFSTimestamp(date: date)
        
        assert(stop.platformIDs.count == 1, "Expecting only one platform per stop")
        
        
        let stop_times = Table("stop_times")
        let trips = Table("trips")
        let tripID = Expression<String>("trip_id")
        let departureTimestamp = Expression<Int>("departure_timestamp")
        let stopID = Expression<String>("stop_id")
        let serviceID = Expression<String>("service_id")
        let query = stop_times.select(stop_times[tripID], departureTimestamp)
            .join(trips, on: stop_times[tripID] == trips[tripID])
            .where(
                stopID == stop.platformIDs[0] &&
                serviceIDs.contains(serviceID) &&
                departureTimestamp >= currentGTFSTimestamp
            )
        
        for row in try db.prepare(query) {
            let tripID = row[tripID]
            let departueGTFSTimestamp = row[departureTimestamp]
            let departueDate = gtfsTimestampToDate(serviceDate: date, gtfsTimestamp: departueGTFSTimestamp)
            tripDepartures[tripID] = departueDate
        }
    } catch {
        print("Unable to fetch scheduled departures")
    }
    
    return tripDepartures
}


func getActiveServices(date: Date, db: Connection) -> [String] {
    var serviceIDs: [String] = []
    
    do {
        // Parse the day of the week as a lowercase name (e.g. "monday").
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: date).lowercased()
        
        // Parse the date as an integer in YYYYMMDD format
        formatter.dateFormat = "yyyyMMdd"
        let dateInteger = Int(formatter.string(from: date))!
        
        // Get the active dates, exclude special dates.
        let query = """
            SELECT service_id
            FROM calendar JOIN calendar_dates ON service_id
            WHERE
                (\(weekday) = 1 AND start_date <= \(dateInteger) AND end_date >= \(dateInteger) AND date != \(dateInteger))
                OR
                (date = \(dateInteger) AND exception_type = 1)
        """
        for row in try db.prepare(query) {
            serviceIDs.append(row[0] as! String)
        }
    } catch {
        print("Unable to fetch active Services")
    }
    
    return serviceIDs
}


func getClosestStopSQL(location: CLLocation, db: Connection) -> Stop? {
    // Set up the SQLite statement we'll need
    var closestStop: Stop = Stop(
        stopID: "Placeholder", stopName: "Placeholder", platformIDs: [], distanceMiles: Double.greatestFiniteMagnitude
    )
    
    let query = "SELECT stop_id, stop_lat, stop_lon, stop_name FROM stops WHERE location_type = 1"
    
    do {
        // Get all stops, calculate distances to find closest stop.
        for row in try db.prepare(query) {
            let distanceMeters = location.distance(from: CLLocation(latitude: row[1]! as! Double, longitude: row[2]! as! Double))
            let distanceMiles = distanceMeters * 0.000621371
            if distanceMiles < closestStop.distanceMiles! {
                let id = row[0] as! String
                let name = row[3] as! String
                closestStop = Stop(stopID: id, stopName: name, platformIDs: [], distanceMiles: distanceMiles)
            }
        }
        
        // Find all platforms for closest stop.
        let platformQuery = "SELECT stop_id FROM stops WHERE parent_station = \"\(closestStop.stopID)\" AND location_type = 0"
        for platformRow in try db.prepare(platformQuery) {
            closestStop.platformIDs.append(platformRow[0] as! String)
        }
        
        return closestStop
    } catch {
        print("Issue fetching closest stop")
    }
    
    return nil
}


func updateDepartures(stop: Stop, feedMessage: TransitRealtime_FeedMessage, departures: [String: Date] ) -> [String: Date] {
    var updatedDepartures: [String: Date] = departures
    // Iterate over the entities in the feed message
    for entity in feedMessage.entity {
        // Check if the entity is a trip update
        if entity.hasTripUpdate {
            let tripUpdate = entity.tripUpdate
            
            // Iterate over the stop times in the trip update
            for stopTimeUpdate in tripUpdate.stopTimeUpdate {
                // Check if the stop ID matches the one we're looking for
                if stop.platformIDs.contains(stopTimeUpdate.stopID) {
                    let timeInterval = TimeInterval(stopTimeUpdate.departure.time)
                    let date = Date(timeIntervalSince1970: timeInterval)
                    
                    // Remove the trip if it was cancelled or has already departed
                    if tripUpdate.trip.scheduleRelationship == .canceled || date.timeIntervalSinceNow < 0{
                        updatedDepartures.removeValue(forKey: tripUpdate.trip.tripID)
                    } else {
                        updatedDepartures[tripUpdate.trip.tripID] = date
                    }
                }
            }
        }
    }
    
    // Return the array of routes and arrival times
    return updatedDepartures
}


func getRouteDepartures(departures: [String: Date], db: Connection) -> [String: [Date]] {
    var routeDepartures: [String: [Date]] = [:]
    
    do {
        for (tripID, departureDate) in departures {
            let routes = Table("routes")
            let trips = Table("trips")
            let routeID = Expression<String>("route_id")
            let routeName = Expression<String>("route_long_name")
            let tripIDColumn = Expression<String>("trip_id")
            let query = routes.select(routeName)
                .join(trips, on: routes[routeID] == trips[routeID])
                .where(
                    tripIDColumn == tripID
                )
            let row = try db.pluck(query)
            if row == nil {
                continue
            }
            var route = row![routeName]
            // Pet peeve: chop off the source of a route, show only destination
            if let range = route.range(of: "to ") {
                route = String(route[range.upperBound...])
            }
            if routeDepartures[route] != nil {
                routeDepartures[route]!.append(departureDate)
            } else {
                routeDepartures[route] = [departureDate]
            }
        }
    } catch {
        print("Error getting route names")
    }
    
    return routeDepartures
}


