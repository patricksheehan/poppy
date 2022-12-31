import CoreData
import SwiftUI
import WidgetKit

struct NearbyStationView: View, Sendable {
    @EnvironmentObject var fetcher: TransitDataFetcher
    
    var body: some View {
        Text(fetcher.closestStop.stopName)
            .font(
                .custom(
                    "RobotoMono-Regular",
                    size: 25,
                    relativeTo: .title
                )
            )
        Text("(" + String(round(fetcher.closestStop.distanceMiles ?? -1.0)) + " miles away)")
            .font(
                .custom(
                    "RobotoMono-Regular",
                    size: 16,
                    relativeTo: .footnote
                )
            )
        List {
            ForEach(fetcher.departuresMinutes.keys.sorted(), id: \.self) {
                routeName in
                HStack{
                    Text(routeName.prefix(18) + ":")
                        .font(
                            .custom(
                                "RobotoMono-Regular",
                                size: 18,
                                relativeTo: .headline
                            )
                        )
                    Text(fetcher.departuresMinutes[routeName]!.map{String($0)}.joined(separator: ", "))
                        .font(
                            .custom(
                                "RobotoMono-Regular",
                                size: 18,
                                relativeTo: .headline
                            )
                        )
                }
            }
        }
        .padding()
        .task {
            try? await fetcher.fetchData()
        }
        .refreshable {
            try? await fetcher.fetchData()
        }
        Text("Last updated: " + (fetcher.lastUpdated ?? ""))
            .font(
                .custom(
                    "RobotoMono-Regular",
                    size: 16,
                    relativeTo: .footnote
                )
            )
    }
}
