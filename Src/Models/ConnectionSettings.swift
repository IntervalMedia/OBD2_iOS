import Foundation

struct BluetoothAdapterDescriptor: Codable, Equatable, Hashable, Identifiable, Sendable {
    let identifier: String
    let name: String
    let signalStrength: Int?

    var id: String { identifier }

    var displayName: String {
        name.isEmpty ? "Unnamed Adapter" : name
    }
}

struct ConnectionSettings: Codable, Equatable {
    enum TransportType: String, Codable, CaseIterable, Identifiable, Sendable {
        case wifi
        case bluetoothLE

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .wifi:
                return "Wi-Fi"
            case .bluetoothLE:
                return "Bluetooth LE"
            }
        }
    }

    var transportType: TransportType = .wifi
    var host: String = "192.168.0.10"
    var port: UInt16 = 35000
    var commandTimeoutSeconds: TimeInterval = 3.0
    var pollingIntervalSeconds: TimeInterval = 1.0
    var maxStoredSamples: Int = 500
    var preferredBluetoothPeripheralID: String?
    var preferredBluetoothPeripheralName: String?

    private enum CodingKeys: String, CodingKey {
        case transportType
        case host
        case port
        case commandTimeoutSeconds
        case pollingIntervalSeconds
        case maxStoredSamples
        case preferredBluetoothPeripheralID
        case preferredBluetoothPeripheralName
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        transportType = try container.decodeIfPresent(TransportType.self, forKey: .transportType) ?? .wifi
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "192.168.0.10"
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? 35000
        commandTimeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .commandTimeoutSeconds) ?? 3.0
        pollingIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .pollingIntervalSeconds) ?? 1.0
        maxStoredSamples = try container.decodeIfPresent(Int.self, forKey: .maxStoredSamples) ?? 500
        preferredBluetoothPeripheralID = try container.decodeIfPresent(String.self, forKey: .preferredBluetoothPeripheralID)
        preferredBluetoothPeripheralName = try container.decodeIfPresent(String.self, forKey: .preferredBluetoothPeripheralName)
    }
}
