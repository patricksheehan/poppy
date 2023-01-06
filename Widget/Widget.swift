import WidgetKit
import SwiftUI
import AsyncLocationKit
import SQLite
import CoreLocation

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DeparturesEntry {
        DeparturesEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DeparturesEntry) -> ()) {
        print("we getting the snapshot")
        if context.isPreview {
            completion(DeparturesEntry.placeholder)
        } else {
            Task {
                let entry = DeparturesEntry(date: Date(), closestStop: sampleStop, departuresMinutes: sampleDepartures)
                completion(entry)
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        print("we getting the timeline")
        Task {
            let gtfsDb = try Connection(GTFS_DB_URL, readonly: true)
            var userLocation:  CLLocation = CLLocation(latitude: 37.764831501887876, longitude: -122.42142043985223)
            let locationManager = AsyncLocationManager(desiredAccuracy: .hundredMetersAccuracy)
            let locationUpdate = try await locationManager.requestLocation()
            switch locationUpdate {
                case .didUpdateLocations(let locations):
                    userLocation = locations.last!
                case .didPaused, .didResume, .none, .didFailWith:
                    print("no location update")
            }
            let closestStop = getClosestStopSQL(location: userLocation, db: gtfsDb)!
            let date = Date()
            let entry = DeparturesEntry(date: date, closestStop: closestStop, departuresMinutes: sampleDepartures)
            let timeline = Timeline(entries: [entry], policy: .after(date.addingTimeInterval(60)))
            completion(timeline)
        }
    }
}

struct DeparturesEntry: TimelineEntry {
    let date: Date
    let closestStop: Stop
    let departuresMinutes: [String: [Int]]
    var isPlaceholder = false
}

extension DeparturesEntry {
    static var stub: DeparturesEntry {
        DeparturesEntry(date: Date(), closestStop: sampleStop, departuresMinutes: sampleDepartures)
    }
    
    static var placeholder: DeparturesEntry {
        DeparturesEntry(date: Date(), closestStop: sampleStop, departuresMinutes: sampleDepartures, isPlaceholder: true)
    }
}

struct PoppyWidgetEntryView : SwiftUI.View {
    var entry: Provider.Entry
    
    var body: some SwiftUI.View {
        Text(entry.closestStop.stopName)
    }
}

struct PoppyWidget: Widget {
    let kind: String = "PoppyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PoppyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("My Widget")
        .description("This is an example widget.")
    }
}
