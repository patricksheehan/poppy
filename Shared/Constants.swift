import Foundation

let GTFS_DB_URL = Bundle.main.path(forResource: "gtfs", ofType: "db")!
let sampleStop = Stop(stopID: "Fake", stopName: "Sample Stop", platformIDs: ["Fake"], distanceMiles: 1.5)
let sampleDepartures = ["Sample Route": [1, 4, 45]]
