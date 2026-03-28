import Foundation

struct ConnectionSettings: Codable, Equatable {
    var host: String = "192.168.0.10"
    var port: UInt16 = 35000
    var commandTimeoutSeconds: TimeInterval = 3.0
    var pollingIntervalSeconds: TimeInterval = 1.0
    var maxStoredSamples: Int = 500
}
