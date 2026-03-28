import Foundation

enum CSVExporter {
    static func makeCSV(samples: [LiveSample]) -> String {
        var rows: [String] = [
            "timestamp,rpm,speed_kph,coolant_temp_c,throttle_position_percent,battery_voltage"
        ]

        for sample in samples {
            rows.append([
                sample.timestamp.iso8601String(),
                sample.rpm.map { String(format: "%.2f", $0) } ?? "",
                sample.speedKph.map(String.init) ?? "",
                sample.coolantTempC.map(String.init) ?? "",
                sample.throttlePositionPercent.map { String(format: "%.2f", $0) } ?? "",
                sample.batteryVoltage.map { String(format: "%.2f", $0) } ?? ""
            ].joined(separator: ","))
        }

        return rows.joined(separator: "\n")
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
