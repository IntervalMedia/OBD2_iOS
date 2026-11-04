import Foundation

/// Fuel type is selected by the user, as in Android; the family byte alone is insufficient.
public enum NissanECUProfile: String, CaseIterable, Sendable, Identifiable {
    case petrol, diesel
    public var id: String { rawValue }
    public func readDTCCommand(family: UInt8) -> String {
        switch (self, family) {
        case (.petrol, 0xA0), (.diesel, 0x70): return "19020F"
        case (.petrol, _): return "17FF00"
        case (.diesel, 5): return "19022F"
        case (.diesel, _): return "1902FF"
        }
    }
    public func clearDTCCommand(family: UInt8) -> String {
        self == .petrol && family != 0xA0 ? "14FF00" : "14FFFFFF"
    }
    public func register(for parameter: NissanParameter) throws -> Register {
        guard self == .diesel else { return parameter.register }
        switch parameter {
        case .rpm: return Register(id: 0x1201, width: 2, scale: Double(Float(bitPattern: 0x3DC81451)), offset: 0)
        case .battery: return Register(id: 0x1105, width: 1, scale: 0.08, offset: 0)
        case .coolant: return Register(id: 0x1101, width: 1, scale: 1, offset: -40)
        case .speed: return Register(id: 0x1102, width: 1, scale: 2, offset: 0)
        case .airFlowVoltage: return Register(id: 0x1205, width: 2, scale: 0.005, offset: 0)
        default: throw DiagnosticError.unsupportedParameter(parameter.rawValue)
        }
    }
}

public struct DiagnosticSample: Sendable {
    public let timestamp: Date
    public let parameter: NissanParameter
    public let value: Double?
    public let error: DiagnosticError?
}

public enum SupportedRegisters {
    public static func decode(response: String, base: UInt16) throws -> Set<UInt16> {
        let command = String(format: "22%04X", base)
        let bytes = try ELMPayload.decode(response: response, command: command)
        guard bytes.count == 7, bytes[0] == 0x62, bytes[1] == UInt8(base >> 8),
              bytes[2] == UInt8(base & 255), base <= UInt16.max - 32 else { throw DiagnosticError.unexpectedResponse }
        return Set((0..<32).compactMap { bit in
            bytes[3 + bit / 8] & (0x80 >> (bit % 8)) != 0 ? base + UInt16(bit + 1) : nil
        })
    }
}
