import Foundation

enum OBDParser {
    static func sanitize(_ response: String) -> String {
        response
            .uppercased()
            .replacingOccurrences(of: "SEARCHING...", with: "")
            .replacingOccurrences(of: "NO DATA", with: "")
            .replacingOccurrences(of: "OK", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    static func parseRPM(_ response: String) -> Double? {
        let hex = sanitize(response)
        guard let range = hex.range(of: "410C"),
              hex.distance(from: range.upperBound, to: hex.endIndex) >= 4 else {
            return nil
        }

        let start = range.upperBound
        let end = hex.index(start, offsetBy: 4)
        let bytes = String(hex[start..<end])

        guard let a = Int(bytes.prefix(2), radix: 16),
              let b = Int(bytes.suffix(2), radix: 16) else {
            return nil
        }

        return Double((256 * a + b) / 4)
    }

    static func parseSpeed(_ response: String) -> Int? {
        let hex = sanitize(response)
        guard let range = hex.range(of: "410D"),
              hex.distance(from: range.upperBound, to: hex.endIndex) >= 2 else {
            return nil
        }

        let start = range.upperBound
        let end = hex.index(start, offsetBy: 2)
        return Int(String(hex[start..<end]), radix: 16)
    }

    static func parseCoolantTemp(_ response: String) -> Int? {
        let hex = sanitize(response)
        guard let range = hex.range(of: "4105"),
              hex.distance(from: range.upperBound, to: hex.endIndex) >= 2 else {
            return nil
        }

        let start = range.upperBound
        let end = hex.index(start, offsetBy: 2)
        guard let raw = Int(String(hex[start..<end]), radix: 16) else {
            return nil
        }
        return raw - 40
    }

    static func parseThrottlePosition(_ response: String) -> Double? {
        let hex = sanitize(response)
        guard let range = hex.range(of: "4111"),
              hex.distance(from: range.upperBound, to: hex.endIndex) >= 2 else {
            return nil
        }

        let start = range.upperBound
        let end = hex.index(start, offsetBy: 2)
        guard let raw = Int(String(hex[start..<end]), radix: 16) else {
            return nil
        }
        return Double(raw) * 100.0 / 255.0
    }

    static func parseBatteryVoltage(_ response: String) -> Double? {
        let cleaned = response
            .uppercased()
            .replacingOccurrences(of: "V", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    static func parseStoredDTCs(_ response: String) -> [DiagnosticTroubleCode] {
        let hex = sanitize(response)
        guard let range = hex.range(of: "43") else { return [] }

        let payload = String(hex[range.upperBound...])
        var result: [DiagnosticTroubleCode] = []
        var index = payload.startIndex

        while payload.distance(from: index, to: payload.endIndex) >= 4 {
            let next = payload.index(index, offsetBy: 4)
            let word = String(payload[index..<next])

            if word == "0000" {
                break
            }

            if let code = decodeDTC(word) {
                result.append(DiagnosticTroubleCode(code: code))
            }

            index = next
        }

        return result
    }

    static func parseVIN(_ response: String) -> String? {
        let hex = sanitize(response)
        guard let range = hex.range(of: "4902") else {
            return nil
        }

        let payload = String(hex[range.upperBound...])
        var bytes: [UInt8] = []
        var idx = payload.startIndex

        while payload.distance(from: idx, to: payload.endIndex) >= 2 {
            let next = payload.index(idx, offsetBy: 2)
            let byteString = String(payload[idx..<next])

            if let value = UInt8(byteString, radix: 16) {
                bytes.append(value)
            }

            idx = next
        }

        let ascii = bytes
            .filter { $0 >= 0x20 && $0 <= 0x7E }
            .map { Character(UnicodeScalar($0)) }

        let vin = String(ascii).trimmingCharacters(in: .whitespacesAndNewlines)
        return vin.isEmpty ? nil : vin
    }

    private static func decodeDTC(_ word: String) -> String? {
        guard word.count == 4,
              let b1 = Int(word.prefix(2), radix: 16),
              let b2 = Int(word.suffix(2), radix: 16) else {
            return nil
        }

        let familyBits = (b1 & 0b11000000) >> 6
        let family: String
        switch familyBits {
        case 0: family = "P"
        case 1: family = "C"
        case 2: family = "B"
        case 3: family = "U"
        default: return nil
        }

        let d1 = (b1 & 0b00110000) >> 4
        let d2 = b1 & 0b00001111
        let d3 = (b2 & 0b11110000) >> 4
        let d4 = b2 & 0b00001111

        return "\(family)\(d1)\(d2)\(d3)\(d4)"
    }
}
