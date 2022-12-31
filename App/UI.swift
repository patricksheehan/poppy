import CoreData
import SwiftUI
import WidgetKit

struct CustomColor {
    static let base03 = Color("solarized_base03")
    static let base02 = Color("solarized_base02")
    static let violet = Color("solarized_violet")
    static let orange = Color("solarized_orange")
}

struct NearbyStationView: View, Sendable {
    @EnvironmentObject var fetcher: TransitDataFetcher
    
    var body: some View {
        VStack {
            Text(fetcher.closestStop.stopName)
                .font(
                    .custom(
                        "RobotoMono-Regular",
                        size: 25,
                        relativeTo: .title
                    )
                )
                .foregroundColor(CustomColor.violet)
            Text("(" + String(round(fetcher.closestStop.distanceMiles ?? -1.0)) + " miles away)")
                .font(
                    .custom(
                        "RobotoMono-Regular",
                        size: 16,
                        relativeTo: .footnote
                    )
                )
                .foregroundColor(CustomColor.violet)
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
                            .foregroundColor(CustomColor.violet)
                        Text(fetcher.departuresMinutes[routeName]!.map{String($0)}.joined(separator: ", "))
                            .font(
                                .custom(
                                    "RobotoMono-Regular",
                                    size: 18,
                                    relativeTo: .headline
                                )
                            )
                            .foregroundColor(CustomColor.orange)
                    }
                }
                .listRowBackground(CustomColor.base02)
            }
            .scrollContentBackground(.hidden)
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
                .foregroundColor(CustomColor.violet)
        }
        .background(CustomColor.base03)
    }
}
