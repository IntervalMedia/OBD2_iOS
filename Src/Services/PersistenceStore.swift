import Foundation

final class PersistenceStore {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let connectionSettings = "connectionSettings"
        static let liveSamples = "liveSamples"
        static let vehicleInfo = "vehicleInfo"
    }

    func loadConnectionSettings() -> ConnectionSettings {
        decode(ConnectionSettings.self, forKey: Key.connectionSettings) ?? ConnectionSettings()
    }

    func saveConnectionSettings(_ settings: ConnectionSettings) {
        encode(settings, forKey: Key.connectionSettings)
    }

    func loadLiveSamples() -> [LiveSample] {
        decode([LiveSample].self, forKey: Key.liveSamples) ?? []
    }

    func saveLiveSamples(_ samples: [LiveSample]) {
        encode(samples, forKey: Key.liveSamples)
    }

    func loadVehicleInfo() -> VehicleInfo {
        decode(VehicleInfo.self, forKey: Key.vehicleInfo) ?? VehicleInfo()
    }

    func saveVehicleInfo(_ info: VehicleInfo) {
        encode(info, forKey: Key.vehicleInfo)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(type, from: data)
    }
}
