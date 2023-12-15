import SQLite
import Foundation
import CoreLocation

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
    // Takes a stop, set of active services, and a date and returns scheduled departures for the current time.
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
            SELECT calendar.service_id
            FROM calendar JOIN calendar_dates ON calendar.service_id = calendar_dates.service_id
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

// Returns the next three departures for the given routes in minutes.
func nextThreeDepartures(departures: [String: [Date]]) -> [String: [Int]] {
    let nextThreeDepartures = departures.mapValues { dates in
        return dates.sorted(by: <).prefix(3)
    }
    var departuresMinutes = nextThreeDepartures.mapValues { dates in
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
    
    return departuresMinutes
}


// Transitland Utils, unused since for now we're sticking with a local GTFS DB.
func makeTransitlandRequest(route: String, params: [String: String]) async -> [String: Any]? {
    do {
        let baseQueryParams = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "apikey", value: TRANSITLAND_API_KEY),
        ]
        let baseTransitlandUrl = URL(string: "https://transit.land/api/v2/rest/" + route)!
        var urlWithParams = URLComponents(url: baseTransitlandUrl, resolvingAgainstBaseURL: false)!
        urlWithParams.queryItems = baseQueryParams + params.map {
            URLQueryItem(name: $0, value: $1)
        }
        print(urlWithParams.url!)
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: urlWithParams.url!))
        let responseObject = (try? JSONSerialization.jsonObject(with: data)) as! [String: Any]
        return responseObject
    } catch {
        print("Error making Transitland request: \(error)")
        return nil
    }
}


func getClosestStationTransitland(location: CLLocation) async -> Stop {
    let params: [String: String] = [
        "lat": String(location.coordinate.latitude),
        "lon": String(location.coordinate.longitude),
        "feed_onestop_id": "f-sf~bay~area~rg",
        "radius": "10000"
    ]
    let stopDict = await makeTransitlandRequest(route: "stops" , params: params)!
    let stop = Stop(stopID: stopDict["onestop_id"] as! String, stopName: stopDict["name"] as! String, platformIDs: [])
    return stop
}
