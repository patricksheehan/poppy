import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DeparturesEntry {
        DeparturesEntry(date: Date(), closestStop: sampleStop)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeparturesEntry) -> ()) {
        let entry = DeparturesEntry(date: Date(), closestStop: sampleStop)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [DeparturesEntry] = []

        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let stop = sampleStop
            let entry = DeparturesEntry(date: entryDate, closestStop: stop)
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct DeparturesEntry: TimelineEntry {
    let date: Date
    let closestStop: Stop
    
}

struct PoppyWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        Text(entry.date, style: .time)
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

struct PoppyWidget_Previews: PreviewProvider {
    static var previews: some View {
        PoppyWidgetEntryView(entry: DeparturesEntry(date: Date(), closestStop: sampleStop))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
