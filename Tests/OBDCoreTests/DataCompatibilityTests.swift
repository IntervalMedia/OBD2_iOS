import XCTest
@testable import OBDCore

final class DataCompatibilityTests: XCTestCase {
    func testLegacySettingsKeepWiFiDefaultsAndSavedConnection() throws {
        let settings = try JSONDecoder().decode(
            ConnectionSettings.self,
            from: Data(#"{"host":"192.168.1.5","port":1234}"#.utf8)
        )
        XCTAssertEqual(settings.transportType, .wifi)
        XCTAssertEqual(settings.host, "192.168.1.5")
        XCTAssertEqual(settings.port, 1234)
        XCTAssertEqual(settings.commandTimeoutSeconds, 3)
        XCTAssertEqual(settings.maxStoredSamples, 500)
    }

    func testBluetoothSettingsRoundTrip() throws {
        var settings = ConnectionSettings()
        settings.transportType = .bluetoothLE
        settings.preferredBluetoothPeripheralID = "fixture-peripheral"
        settings.preferredBluetoothPeripheralName = "Diagnostic adapter"
        let restored = try JSONDecoder().decode(ConnectionSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
    }

    func testCSVPreservesColumnOrderAndMissingMeasurements() {
        let sample = LiveSample(timestamp: Date(timeIntervalSince1970: 0), rpm: 1726.25,
                                speedKph: 100, coolantTempC: nil,
                                throttlePositionPercent: 50, batteryVoltage: 12.8)
        let csv = CSVExporter.makeCSV(samples: [sample])
        XCTAssertEqual(csv, "timestamp,rpm,speed_kph,coolant_temp_c,throttle_position_percent,battery_voltage\n1970-01-01T00:00:00Z,1726.25,100,,50.00,12.80")
    }

    func testNissanCSVLabelsLiveMeasurementsWithUnits() {
        let timestamp = Date(timeIntervalSince1970: 0)
        let records = [
            NissanLogRecord(timestamp: timestamp, source: "live", parameter: .rpm, value: 1250),
            NissanLogRecord(timestamp: timestamp, source: "live", parameter: .battery, value: 12.8)
        ]
        XCTAssertEqual(NissanCSVExporter.makeCSV(samples: records),
                       "timestamp,source,parameter,value,unit\n\"1970-01-01T00:00:00Z\",\"live\",\"Engine RPM\",\"1250.0\",\"rpm\"\n\"1970-01-01T00:00:00Z\",\"live\",\"Battery voltage\",\"12.8\",\"V\"")
    }

    func testNissanCSVQuotesEmbeddedSourcePunctuation() {
        let record = NissanLogRecord(timestamp: Date(timeIntervalSince1970: 0),
                                     source: "Live, adapter \"A\"", parameter: .coolant, value: 83)
        XCTAssertTrue(NissanCSVExporter.makeCSV(samples: [record]).contains("\"Live, adapter \"\"A\"\"\""))
    }
}
