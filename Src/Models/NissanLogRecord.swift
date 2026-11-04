import Foundation
#if canImport(NissanCore)
import NissanCore
#endif

struct NissanLogRecord {
    let timestamp: Date
    let source: String
    let parameter: NissanParameter
    let value: Double
}

enum NissanCSVExporter {
    static func makeCSV(samples: [NissanLogRecord]) -> String {
        let rows = samples.map { sample in
            [sample.timestamp.ISO8601Format(), sample.source, sample.parameter.rawValue,
             String(sample.value), sample.parameter.unit].map(escape).joined(separator: ",")
        }
        return (["timestamp,source,parameter,value,unit"] + rows).joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
