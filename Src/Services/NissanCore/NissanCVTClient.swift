import Foundation

/// Read-only Consult III CVT information for ECUs implementing the 21xx records.
/// Offsets come from EconTool 4.11 uk0/rk0/wk0; compatibility needs vehicle validation.
public struct NissanCVTInformation: Sendable, Equatable {
    public let identifier: String
    public let calibrationIDs: [String]
    public let deteriorationCounter: UInt32
    public let cvtA: UInt8
    public let cvtB: UInt16
    public let highTemperatureCount: Double
    public let veryHighTemperatureCount: Double

    public init(identity: String, calibration: String, deterioration: String, counters: String) throws {
        let id = try Self.record(identity, command: "2183", minimum: 5)
        guard id.prefix(5).allSatisfy({ (0x20...0x7E).contains($0) }) else {
            throw DiagnosticError.malformedResponse
        }
        let calibrationBytes = try Self.record(calibration, command: "2102", minimum: 12)
        let deteriorationBytes = try Self.record(deterioration, command: "2103", minimum: 4)
        let counterBytes = try Self.record(counters, command: "2110", minimum: 26)
        identifier = "31036-" + String(decoding: id.prefix(5), as: UTF8.self)
        calibrationIDs = stride(from: 0, to: 12, by: 2).map {
            String(format: "%02X%02X", calibrationBytes[$0], calibrationBytes[$0 + 1])
        }
        // Keep the full unsigned counter; the source app stores it in a lossy Float.
        deteriorationCounter = deteriorationBytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        cvtA = counterBytes[8]
        cvtB = Self.word(counterBytes, at: 0)
        highTemperatureCount = Double(Self.word(counterBytes, at: 4)) / 6
        veryHighTemperatureCount = Double(Self.word(counterBytes, at: 24)) / 6
    }

    private static func record(_ response: String, command: String, minimum: Int) throws -> [UInt8] {
        let bytes = try ELMPayload.decode(response: response, command: command)
        guard bytes.count >= minimum + 2, bytes[0] == 0x61,
              bytes[1] == UInt8(command.suffix(2), radix: 16) else {
            throw DiagnosticError.unexpectedResponse
        }
        return Array(bytes.dropFirst(2))
    }

    private static func word(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
}

/// Owns a separate 7E1/7E9 session; never use concurrently with an ECM client.
public actor NissanCVTClient {
    private let transport: any ELMTransport
    private var initialized = false
    private var busy = false
    private var generation = 0

    public init(transport: any ELMTransport) { self.transport = transport }

    public func initialize() async throws {
        guard !busy else { throw DiagnosticError.busy }
        busy = true
        initialized = false
        let session = generation
        defer { busy = false }
        do {
            let banner = try await exchange("ATZ", session: session)
            guard banner.uppercased().contains("ELM") else {
                throw DiagnosticError.adapter("No ELM identification banner")
            }
            // Explicit normalized framing is an OBDMVP choice. Address, timing and
            // flow-control sequence are recovered from EconTool uk0.b().
            for command in ["ATE0", "ATL0", "ATH0", "ATS0", "ATCAF1", "ATAL"] {
                try await configure(command, session: session)
            }
            try await configureBus(slow: false, session: session)
            _ = try await exchange("2101", session: session)
            var probe = try await exchange("2101", session: session)
            if probe.uppercased().filter({ !$0.isWhitespace && $0 != ">" }) == "NODATA" {
                try await configureBus(slow: true, session: session)
                probe = try await exchange("2101", session: session)
            }
            let bytes = try ELMPayload.decode(response: probe, command: "2101")
            guard bytes.count > 2, bytes[0] == 0x61, bytes[1] == 0x01 else {
                throw DiagnosticError.unsupportedParameter("CVT 21xx information records")
            }
            initialized = true
        } catch {
            await transport.close()
            throw error
        }
    }

    public func readInformation() async throws -> NissanCVTInformation {
        guard initialized else { throw DiagnosticError.notInitialized }
        guard !busy else { throw DiagnosticError.busy }
        busy = true
        let session = generation
        defer { busy = false }
        let identity = try await exchange("2183", session: session)
        let calibration = try await exchange("2102", session: session)
        let deterioration = try await exchange("2103", session: session)
        let counters = try await exchange("2110", session: session)
        return try NissanCVTInformation(identity: identity, calibration: calibration,
                                        deterioration: deterioration, counters: counters)
    }

    public func close() async {
        initialized = false
        generation += 1
        await transport.close()
    }

    private func configureBus(slow: Bool, session: Int) async throws {
        for command in ["ATTP6", slow ? "ATST64" : "ATST32", slow ? "ATAT0" : "ATAT2",
                        "ATSH7E1", "ATCRA7E9", "ATFCSH7E1", "ATFCSD300000", "ATFCSM1"] {
            try await configure(command, session: session)
        }
        let response = try await exchange("10C0", session: session)
        let bytes = try ELMPayload.decode(response: response, command: "10C0")
        guard bytes.count >= 2, bytes[0] == 0x50, bytes[1] == 0xC0 else {
            throw DiagnosticError.unexpectedResponse
        }
    }

    private func configure(_ command: String, session: Int) async throws {
        let response = try await exchange(command, session: session)
        guard response.uppercased().split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == ">" })
            .contains(where: { $0.trimmingCharacters(in: .whitespaces) == "OK" }) else {
            throw DiagnosticError.adapter("\(command) was not acknowledged")
        }
    }

    private func exchange(_ command: String, session: Int) async throws -> String {
        try Task.checkCancellation()
        guard generation == session else { throw CancellationError() }
        let response = try await transport.exchange(command, timeout: 2)
        try Task.checkCancellation()
        guard generation == session else { throw CancellationError() }
        return response
    }
}
