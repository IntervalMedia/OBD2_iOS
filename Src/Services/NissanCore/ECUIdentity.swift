import Foundation

public enum ELMPayload {
    public static func decode(response: String, command: String) throws -> [UInt8] {
        guard response.contains(":") else { return try ELMResponse.payload(response, command: command) }
        let lines = response.uppercased().replacingOccurrences(of: ">", with: "\r")
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map { $0.filter { !$0.isWhitespace } }.filter { !$0.isEmpty && $0 != command.uppercased() }
        guard let first = lines.first, first.count <= 3, let length = Int(first, radix: 16),
              length > 0, length <= 4095 else { throw DiagnosticError.malformedResponse }
        var bytes: [UInt8] = []
        for (index, line) in lines.dropFirst().enumerated() {
            let pieces = line.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2, Int(pieces[0], radix: 16) == index % 16 else { throw DiagnosticError.malformedResponse }
            let text = Array(pieces[1])
            guard !text.isEmpty, text.count % 2 == 0, text.count <= 14 else { throw DiagnosticError.malformedResponse }
            let segment = try Swift.stride(from: 0, to: text.count, by: 2).map { position -> UInt8 in
                guard let byte = UInt8(String(text[position...position + 1]), radix: 16) else { throw DiagnosticError.malformedResponse }
                return byte
            }
            let expected = min(index == 0 ? 6 : 7, length - bytes.count)
            guard expected > 0, segment.count == expected else { throw DiagnosticError.malformedResponse }
            bytes += segment
        }
        guard bytes.count == length else { throw DiagnosticError.malformedResponse }
        return bytes
    }
}

public struct ECUIdentity: Sendable, Equatable {
    public let identifier: String
    public let family: UInt8
    public init(response: String, command: String) throws {
        let bytes = try ELMPayload.decode(response: response, command: command)
        let sub: UInt8 = command.uppercased() == "2183" ? 0x83 : 0xFE
        guard ["2183", "21FE"].contains(command.uppercased()), bytes.count >= 8,
              bytes[0] == 0x61, bytes[1] == sub,
              bytes[2..<7].allSatisfy({ (0x20...0x7E).contains($0) }) else { throw DiagnosticError.unexpectedResponse }
        identifier = String(decoding: bytes[2..<7], as: UTF8.self)
        family = bytes[7]
    }
}

public struct TroubleCode: Sendable, Equatable, Identifiable {
    public let code: String
    public let rawRecord: [UInt8]
    public var status: UInt8 { rawRecord.last! }
    public var id: String { rawRecord.map { String(format: "%02X", $0) }.joined() }
    public static func decode(response: String, command: String) throws -> [TroubleCode] {
        let bytes = try ELMPayload.decode(response: response, command: command)
        let start: Int
        let stride: Int
        if command.uppercased() == "17FF00" {
            guard bytes.count >= 2, bytes[0] == 0x57, bytes.count == 2 + Int(bytes[1]) * 3 else { throw DiagnosticError.malformedResponse }
            start = 2; stride = 3
        } else {
            guard ["19020F", "19022F", "1902FF"].contains(command.uppercased()), bytes.count >= 3,
                  bytes[0] == 0x59, bytes[1] == 0x02, (bytes.count - 3) % 4 == 0 else { throw DiagnosticError.malformedResponse }
            start = 3; stride = 4
        }
        return Swift.stride(from: start, to: bytes.count, by: stride).map { index in
            let record = Array(bytes[index..<index+stride])
            let prefix = ["P", "C", "B", "U"][Int(record[0] >> 6)]
            let code = prefix + String(format: "%01X%01X%02X", (record[0] >> 4) & 3, record[0] & 15, record[1])
            return TroubleCode(code: code, rawRecord: record)
        }
    }
}
