import BackgroundTasks
import SwiftUI

@main
struct Poppy: App {
    @StateObject private var fetcher = TransitDataFetcher()
    
    var body: some Scene {
        return WindowGroup {
            NearbyStationView()
                .environmentObject(fetcher)
        }
    }
}
