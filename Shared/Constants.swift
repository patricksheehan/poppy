import Foundation
import SwiftUI

let GTFS_DB_URL = Bundle.main.path(forResource: "gtfs", ofType: "db")!
let TRANSITLAND_API_KEY = Bundle.main.infoDictionary!["TRANSITLAND_API_KEY"] as! String
let sampleStop = Stop(stopID: "Fake", stopName: "Sample Stop", platformIDs: ["Fake"], distanceMiles: 1.5)
let sampleDepartures = ["Sample Route": [1, 4, 45]]

enum FetchError: Error {
    case badRequest
    case badJSON
}

struct CustomColor {
    static let base03 = Color("solarized_base03")
    static let base02 = Color("solarized_base02")
    static let violet = Color("solarized_violet")
    static let orange = Color("solarized_orange")
    static let yellow = Color("solarized_yellow")
    static let magenta = Color("solarized_magenta")
    static let logoOrange = Color("logo_orange")
    static let logoPurple = Color("logo_purple")
}
