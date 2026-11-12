import Foundation

/// NC3 petrol ECM capabilities recovered from EconTool 4.11 jk0.B/gk0.
/// Discovery reports ECU support; it does not establish vehicle prerequisites.
public struct NissanWorkSupportCapabilities: Sendable, Equatable {
    public let activeTests: Set<UInt8>
    public let learnings: Set<UInt8>
    public let corrections: Set<UInt8>

    public static func decodeMask(_ response: String, service: UInt8, base: UInt8) throws -> Set<UInt8> {
        guard [0x30, 0x31, 0x3B].contains(service), base <= 0xE0, base % 32 == 0 else {
            throw DiagnosticError.unexpectedResponse
        }
        let command = String(format: "%02X%02X", service, base)
        let bytes = try ELMPayload.decode(response: response, command: command)
        guard bytes.count == 6, bytes[0] == service + 0x40, bytes[1] == base else {
            throw DiagnosticError.unexpectedResponse
        }
        // Bit 32 is not a function ID. EconTool enumerates only bits 1…31.
        var supported: Set<UInt8> = []
        for bit in 0..<31 {
            let mask: UInt8 = 0x80 >> (bit % 8)
            if bytes[2 + bit / 8] & mask != 0 {
                supported.insert(base + UInt8(bit + 1))
            }
        }
        return supported
    }
}

public enum NissanLearning: UInt8, CaseIterable, Sendable, Identifiable {
    case idleAirVolume = 3
    case fuelTrimReset = 6
    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .idleAirVolume: return "Idle air volume learning"
        case .fuelTrimReset: return "Fuel trim reset"
        }
    }
    // Closed-throttle (04) is discoverable but omitted: EconTool declares success
    // unconditionally, so the supplied artifact does not establish completion semantics.
}
