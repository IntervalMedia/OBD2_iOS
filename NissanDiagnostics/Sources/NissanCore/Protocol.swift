import Foundation

public enum DiagnosticError: Error, LocalizedError, Equatable {
    case adapter(String), malformedResponse, unexpectedResponse, negativeResponse(UInt8), notInitialized, busy, unsupportedParameter(String)
    public var errorDescription: String? {
        switch self {
        case .adapter(let message): return "Adapter: \(message)"
        case .malformedResponse: return "The adapter returned malformed or incomplete data."
        case .unexpectedResponse: return "The ECU response does not match the requested register."
        case .negativeResponse(let code): return String(format: "ECU rejected the request (NRC %02X).", code)
        case .notInitialized: return "Connect and initialize the adapter first."
        case .unsupportedParameter(let name): return "No recovered mapping for \(name) in the selected ECU profile."
        case .busy: return "A diagnostic request is already running."
        }
    }
}

public protocol ELMTransport: Sendable {
    func exchange(_ command: String) async throws -> String
    func close() async
    func exchange(_ command: String, timeout: TimeInterval) async throws -> String
}

public extension ELMTransport {
    /// Existing transports remain compatible; override to honor operation-specific receive timeouts.
    func exchange(_ command: String, timeout: TimeInterval) async throws -> String {
        try await exchange(command)
    }
}

/// ELM formatted payloads with CAN headers disabled (ATH0), spaces optional.
/// Headered CAN and raw ISO-TP frames are deliberately rejected.
public enum ELMResponse {
    public static func payload(_ response: String, command: String) throws -> [UInt8] {
        let normalized = response.uppercased()
        for failure in ["NO DATA", "STOPPED", "UNABLE TO CONNECT", "CAN ERROR", "BUS ERROR", "BUFFER FULL", "ERROR", "?"] {
            if normalized.contains(failure) { throw DiagnosticError.adapter(failure) }
        }
        let lines = normalized.replacingOccurrences(of: ">", with: "\r")
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map { $0.filter { !$0.isWhitespace } }
            .filter { !$0.isEmpty && $0 != command.uppercased() && $0 != "SEARCHING..." }
        guard lines.count == 1, let line = lines.first, line.count % 2 == 0, line.count <= 8192 else {
            throw DiagnosticError.malformedResponse
        }
        let characters = Array(line)
        let bytes = try stride(from: 0, to: characters.count, by: 2).map { index -> UInt8 in
            guard let byte = UInt8(String(characters[index...index+1]), radix: 16) else {
                throw DiagnosticError.malformedResponse
            }
            return byte
        }
        if bytes.count == 3, bytes[0] == 0x7F { throw DiagnosticError.negativeResponse(bytes[2]) }
        return bytes
    }
}

public struct Register: Sendable, Equatable {
    public let id: UInt16
    public let width: Int
    public let scale: Double
    public let offset: Double
    public init(id: UInt16, width: Int, scale: Double, offset: Double) {
        self.id = id; self.width = width; self.scale = scale; self.offset = offset
    }
    public var command: String { String(format: "22%04X", id) }
    public func decode(_ response: String) throws -> Double {
        let bytes = try ELMResponse.payload(response, command: command)
        guard (1...2).contains(width), bytes.count == 3 + width else { throw DiagnosticError.malformedResponse }
        guard bytes[0] == 0x62, bytes[1] == UInt8(id >> 8), bytes[2] == UInt8(id & 255) else {
            throw DiagnosticError.unexpectedResponse
        }
        return Double(bytes.dropFirst(3).reduce(0) { $0 * 256 + Int($1) }) * scale + offset
    }
}

/// Recovered petrol ECM table; ECU support varies by vehicle. No generic OBD fallback.
public enum NissanParameter: String, CaseIterable, Sendable, Identifiable {
    case rpm = "Engine RPM", coolant = "Coolant temperature", intakeAir = "Intake air temperature"
    case speed = "Vehicle speed", battery = "Battery voltage", throttle = "Throttle sensor voltage"
    case maf = "Mass air flow", ignition = "Ignition timing", airFlowVoltage = "Air flow sensor voltage"
    public var id: String { rawValue }
    public var command: String { register.command }
    public var unit: String {
        switch self {
        case .rpm: return "rpm"
        case .coolant, .intakeAir: return "°C"
        case .speed: return "km/h"
        case .battery, .throttle, .airFlowVoltage: return "V"
        case .maf: return "g/s"
        case .ignition: return "°"
        }
    }
    public var register: Register {
        switch self {
        case .rpm: return Register(id: 0x1201, width: 2, scale: 12.5, offset: 0)
        case .coolant: return Register(id: 0x1101, width: 1, scale: 1, offset: -50)
        case .intakeAir: return Register(id: 0x1106, width: 1, scale: 1, offset: -50)
        case .speed: return Register(id: 0x121A, width: 2, scale: 0.1, offset: 0)
        case .battery: return Register(id: 0x1103, width: 1, scale: 0.08, offset: 0)
        case .throttle: return Register(id: 0x120F, width: 2, scale: 0.005, offset: 0)
        case .maf: return Register(id: 0x1209, width: 2, scale: 0.01, offset: 0)
        case .ignition: return Register(id: 0x110A, width: 1, scale: -1, offset: 110)
        case .airFlowVoltage: return Register(id: 0x1204, width: 2, scale: 0.005, offset: 0)
        }
    }
}
