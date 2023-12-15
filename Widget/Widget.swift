import WidgetKit
import SwiftUI
import AsyncLocationKit
import SQLite
import CoreLocation
import AppIntents
import Intents

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DeparturesEntry {
        DeparturesEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DeparturesEntry) -> ()) {
        // Return a placeholder or initial snapshot if needed
        let entry = DeparturesEntry(date: Date(), closestStop: sampleStop, departuresMinutes: sampleDepartures)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [DeparturesEntry] = []

        // Fetch transit data and update the timeline
        fetchData { result in
            switch result {
            case .success(let (closestStop, departures)):
                let currentDate = Date()
                let entry = DeparturesEntry(date: currentDate, closestStop: closestStop, departuresMinutes: departures)
                entries.append(entry)
            case .failure(let error):
                print("Error fetching data: \(error)")
            }

            // Define the refresh policy based on your requirements
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date()
            let timeline = Timeline(entries: entries, policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }

    private func fetchData(completion: @escaping (Swift.Result<(Stop, [String: [Int]]), Error>) -> ()) {
        // Create an instance of your TransitDataFetcher
        let dataFetcher = TransitDataFetcher()

        // Perform the data fetching asynchronously
        Task {
            do {
                // Fetch data using your existing fetchData method
                try await dataFetcher.fetchData()

                // Access the latest transit data from the dataFetcher
                let closestStop = dataFetcher.closestStop
                let departuresMinutes = dataFetcher.departuresMinutes

                // Call the completion handler with the fetched data
                completion(.success((closestStop, departuresMinutes)))
            } catch {
                // Handle any errors that occur during data fetching
                completion(.failure(error))
            }
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

struct ReloadWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Reload widget"
    static var description = IntentDescription("Reload widget.")

    init() {}

    func perform() async throws -> some IntentResult {
        return .result()
    }
}


@available(iOSApplicationExtension 17.0, *)
struct ReloadView: SwiftUI.View {

    var body: some SwiftUI.View {
        Button(intent: ReloadWidgetIntent()) {
            Text("Refresh")
        }
    }
}


@available(iOS 17.0, *)
struct PoppyWidgetEntryView : SwiftUI.View {
    var entry: Provider.Entry
    
    var body: some SwiftUI.View {
        HStack(alignment: .center, spacing: nil, content: {
            VStack(content: {
                Text(entry.closestStop.stopName)
                    .font(
                        .custom(
                            "RobotoMono-Regular",
                            size: 18,
                            relativeTo: .headline
                        )
                    )
                    .foregroundColor(CustomColor.logoOrange)
                    .alignmentGuide(.leading) { d in d[.leading] }
                ForEach(entry.departuresMinutes.keys.sorted(), id: \.self) {
                    routeName in
                    HStack {
                        Text(routeName + ":")
                            .font(
                                .custom(
                                    "RobotoMono-Regular",
                                    size: 18,
                                    relativeTo: .headline
                                )
                            )
                            .foregroundColor(CustomColor.violet)
                            .scaledToFit()
                        Spacer()
                        Text(entry.departuresMinutes[routeName]!.map{String($0)}.joined(separator: ", "))
                            .font(
                                .custom(
                                    "RobotoMono-Regular",
                                    size: 18,
                                    relativeTo: .headline
                                )
                            )
                            .foregroundColor(CustomColor.magenta)
                    }
                }
                Spacer()
                HStack (content: {
                    Text("Last updated:")
                    Text(entry.date, style: .relative)
                        .invalidatableContent()
                    ReloadView()
                })
                .font(
                    .custom(
                        "RobotoMono-Regular",
                        size: 14,
                        relativeTo: .footnote
                    )
                )
                .foregroundColor(CustomColor.logoOrange)
            })
            .background(CustomColor.base03)
            .containerBackground(CustomColor.base03, for: .widget)
            Spacer()
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@available(iOS 17.0, *)
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
