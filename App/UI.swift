import CoreData
import SwiftUI
import WidgetKit

struct NearbyStationView: View, Sendable {
    @EnvironmentObject var fetcher: TransitDataFetcher
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        VStack {
            VStack{
                Text(fetcher.closestStop.stopName)
                    .font(
                        .custom(
                            "RobotoMono-Regular",
                            size: 22,
                            relativeTo: .title
                        )
                    )
                    .foregroundColor(CustomColor.logoOrange)
                Text("(" + String(round((fetcher.closestStop.distanceMiles  ?? -1.0)*10)/10.0) + " miles away)")
                    .font(
                        .custom(
                            "RobotoMono-Regular",
                            size: 14,
                            relativeTo: .footnote
                        )
                    )
                    .foregroundColor(CustomColor.logoOrange)
            }
            List {
                ForEach(fetcher.departuresMinutes.keys.sorted(), id: \.self) {
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
                        Text(fetcher.departuresMinutes[routeName]!.map{String($0)}.joined(separator: ", "))
                            .font(
                                .custom(
                                    "RobotoMono-Regular",
                                    size: 18,
                                    relativeTo: .headline
                                )
                            )
                            .foregroundColor(CustomColor.violet)
                    }
                }
                .listRowBackground(CustomColor.base03)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .refreshable {
                try? await fetcher.fetchData()
            }
            HStack{
                Text("Last updated:")
                if fetcher.lastUpdated != nil {
                    Text(fetcher.lastUpdated!, style: .relative)
                    Text("ago")
                }

            }
            .font(
                .custom(
                    "RobotoMono-Regular",
                    size: 14,
                    relativeTo: .footnote
                )
            )
            .foregroundColor(CustomColor.logoOrange)
        }
        .background(CustomColor.base03)
        .task {
            do {
                try await fetcher.fetchData()
            } catch {
                print("Unexpected error: \(error)")
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    try? await fetcher.fetchData()
                }
            }
        }
    }
}
