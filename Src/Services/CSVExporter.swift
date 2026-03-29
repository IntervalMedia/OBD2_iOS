import Foundation

enum CSVExporter {
    static func makeCSV(samples: [LiveSample]) -> String {
        var rows: [String] = [csvHeader]

        for sample in samples {
            rows.append(csvRow(for: sample))
        }

        return rows.joined(separator: "\n")
    }

    private static let csvHeader = "timestamp,rpm,speed_kph,coolant_temp_c,throttle_position_percent,battery_voltage"

    private static func csvRow(for sample: LiveSample) -> String {
        let timestamp = sample.timestamp.iso8601String()
        let rpm = sample.rpm.map { String(format: "%.2f", $0) } ?? ""
        let speed = sample.speedKph.map(String.init) ?? ""
        let coolant = sample.coolantTempC.map(String.init) ?? ""
        let throttle = sample.throttlePositionPercent.map { String(format: "%.2f", $0) } ?? ""
        let batteryVoltage = sample.batteryVoltage.map { String(format: "%.2f", $0) } ?? ""

        return [
            timestamp,
            rpm,
            speed,
            coolant,
            throttle,
            batteryVoltage
        ].joined(separator: ",")
    }

    static func writeCSVToTemporaryFile(samples: [LiveSample]) throws -> URL {
        let csv = makeCSV(samples: samples)
        let fileName = "obd-log-\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            throw AppError.exportFailed
        }
    }
}
