import Foundation

/// One command in flight. Rejects concurrent calls across actor reentrancy.
public actor DiagnosticClient {
    private let transport: any ELMTransport
    public let profile: NissanECUProfile
    private var initialized = false
    private var busy = false
    private var generation = 0
    private var identity: ECUIdentity?
    public init(transport: any ELMTransport, profile: NissanECUProfile = .petrol) { self.transport = transport; self.profile = profile }

    public func initialize() async throws {
        guard !busy else { throw DiagnosticError.busy }
        busy = true
        initialized = false
        identity = nil
        let session = generation
        defer { busy = false }
        do {
            let reset = try await transport.exchange("ATZ", timeout: 2).uppercased()
            guard reset.contains("ELM") else { throw DiagnosticError.adapter("No ELM identification banner") }
            // Normalized framing is a reconstruction choice; Nissan session sequence is recovered.
            for command in ["ATE0", "ATL0", "ATH0", "ATCAF1", "ATSH7E0", "ATSP6", "ATS0", "ATAL"] {
                try Task.checkCancellation()
                guard generation == session else { throw CancellationError() }
                let reply = try await transport.exchange(command, timeout: 2)
                guard reply.uppercased().split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == ">" })
                    .contains(where: { $0.trimmingCharacters(in: .whitespaces) == "OK" }) else {
                    throw DiagnosticError.adapter("\(command) failed: \(reply.prefix(100))")
                }
            }
            for command in ["1081", "10C0"] {
                try Task.checkCancellation()
                guard generation == session else { throw CancellationError() }
                let response = try await transport.exchange(command, timeout: command == "1081" ? 2 : 0.7)
                let payload = try ELMResponse.payload(response, command: command)
                guard payload.count >= 2, payload[0] == 0x50,
                      payload[1] == UInt8(command.suffix(2), radix: 16) else {
                    throw DiagnosticError.unexpectedResponse
                }
            }
            guard generation == session else { throw CancellationError() }
            try Task.checkCancellation()
            initialized = true
        } catch {
            await transport.close()
            throw error
        }
    }

    public func read(parameter: NissanParameter) async throws -> Double {
        guard initialized else { throw DiagnosticError.notInitialized }
        return try await read(register: profile.register(for: parameter))
    }

    public func read(register: Register) async throws -> Double {
        guard initialized else { throw DiagnosticError.notInitialized }
        guard !busy else { throw DiagnosticError.busy }
        busy = true
        let session = generation
        defer { busy = false }
        try Task.checkCancellation()
        let response = try await transport.exchange(register.command, timeout: 0.5)
        guard generation == session else { throw CancellationError() }
        try Task.checkCancellation()
        return try register.decode(response)
    }

    public func identifyECU() async throws -> ECUIdentity {
        guard initialized else { throw DiagnosticError.notInitialized }
        guard !busy else { throw DiagnosticError.busy }
        busy = true
        let session = generation
        defer { busy = false }
        identity = nil
        let result: ECUIdentity
        do {
            result = try ECUIdentity(response: await transport.exchange("2183", timeout: 2), command: "2183")
        } catch is DiagnosticError {
            try Task.checkCancellation()
            guard generation == session else { throw CancellationError() }
            result = try ECUIdentity(response: await transport.exchange("21FE", timeout: 2), command: "21FE")
        }
        guard generation == session else { throw CancellationError() }
        identity = result
        return result
    }

    public func readTroubleCodes() async throws -> [TroubleCode] {
        try await waitForIdle()
        guard initialized, let identity else { throw DiagnosticError.notInitialized }
        guard !busy else { throw DiagnosticError.busy }
        busy = true
        let session = generation
        defer { busy = false }
        try await enterDiagnosticSession(session: session)
        let command = profile.readDTCCommand(family: identity.family)
        let response = try await transport.exchange(command, timeout: 0.5)
        guard generation == session else { throw CancellationError() }
        return try TroubleCode.decode(response: response, command: command)
    }

    /// Sends exactly one clear request. Never called automatically by logging or reads.
    /// The caller must invoke this explicitly; a lost reply must not trigger an automatic retry.
    public func clearTroubleCodes() async throws {
        try await waitForIdle()
        guard initialized, let identity else { throw DiagnosticError.notInitialized }
        guard !busy else { throw DiagnosticError.busy }
        busy = true
        let session = generation
        defer { busy = false }
        try await enterDiagnosticSession(session: session)
        let command = profile.clearDTCCommand(family: identity.family)
        let response = try await transport.exchange(command, timeout: 0.5)
        guard generation == session else { throw CancellationError() }
        let bytes = try ELMPayload.decode(response: response, command: command)
        guard bytes == [0x54] else { throw DiagnosticError.unexpectedResponse }
    }

    private func waitForIdle() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while busy {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw DiagnosticError.busy }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    public func prepareDataLogging() async throws {
        try await waitForIdle()
        guard initialized else { throw DiagnosticError.notInitialized }
        busy = true
        defer { busy = false }
        try await enterDiagnosticSession(session: generation)
    }

    private func enterDiagnosticSession(session: Int) async throws {
        try Task.checkCancellation()
        guard generation == session else { throw CancellationError() }
        let response = try await transport.exchange("10C0", timeout: 0.7)
        guard generation == session else { throw CancellationError() }
        let bytes = try ELMPayload.decode(response: response, command: "10C0")
        guard bytes.count >= 2, bytes[0] == 0x50, bytes[1] == 0xC0 else { throw DiagnosticError.unexpectedResponse }
    }

    public func supportedRegisters(base: UInt16) async throws -> Set<UInt16> {
        guard initialized else { throw DiagnosticError.notInitialized }
        guard !busy else { throw DiagnosticError.busy }
        busy = true
        let session = generation
        defer { busy = false }
        let response = try await transport.exchange(String(format: "22%04X", base), timeout: 0.7)
        guard generation == session else { throw CancellationError() }
        return try SupportedRegisters.decode(response: response, base: base)
    }

    /// Response-driven sequential polling, matching Android p4/l3. No fixed parallel PID burst.
    /// Transport failures stop the cycle; ECU-level failures remain attached to their sample.
    public func readCycle(parameters: [NissanParameter]) async throws -> [DiagnosticSample] {
        var samples: [DiagnosticSample] = []
        for parameter in parameters {
            try Task.checkCancellation()
            do {
                let value = try await read(parameter: parameter)
                samples = samples + [DiagnosticSample(timestamp: Date(), parameter: parameter, value: value, error: nil)]
            } catch let error as DiagnosticError {
                switch error {
                case .busy, .notInitialized: throw error
                default: samples = samples + [DiagnosticSample(timestamp: Date(), parameter: parameter, value: nil, error: error)]
                }
            }
        }
        return samples
    }

    public func close() async {
        initialized = false
        identity = nil
        generation += 1
        await transport.close()
    }
}
