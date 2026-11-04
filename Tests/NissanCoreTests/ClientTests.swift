import XCTest
@testable import NissanCore

final class ClientTests: XCTestCase {
    func testIdentityAndFamilySelectedDTCRequest() async throws {
        for family: UInt8 in [1, 0xA0] {
            let transport = FixtureTransport(family: family)
            let client = DiagnosticClient(transport: transport)
            try await client.initialize()
            let identity = try await client.identifyECU()
            XCTAssertEqual(identity.identifier, "ABCDE")
            let codes = try await client.readTroubleCodes()
            XCTAssertEqual(codes.map(\.code), ["P0123"])
            let commands = await transport.commands
            XCTAssertEqual(commands.last, family == 0xA0 ? "19020F" : "17FF00")
            await client.close()
            do { _ = try await client.read(parameter: .rpm); XCTFail() } catch {}
        }
    }
    func testIdentityFallbackAndDTCRequiresIdentity() async throws {
        let client = DiagnosticClient(transport: FixtureTransport(fallback: true))
        try await client.initialize()
        do { _ = try await client.readTroubleCodes(); XCTFail() } catch {}
        let identity = try await client.identifyECU()
        XCTAssertEqual(identity.family, 1)
    }
    func testInitializationFailures() async {
        for failure in ["ATZ", "ATE0", "1081", "10C0"] {
            let transport = FixtureTransport(failure: failure)
            let client = DiagnosticClient(transport: transport)
            do { try await client.initialize(); XCTFail(failure) } catch {}
            let closed = await transport.closed
            XCTAssertTrue(closed)
        }
    }
    func testParameterMappingsAndErrorDescriptions() throws {
        let expected: [(NissanParameter, String, String, Double)] = [
            (.rpm, "221201", "rpm", 1250), (.coolant, "221101", "°C", 50),
            (.intakeAir, "221106", "°C", 50), (.speed, "22121A", "km/h", 10),
            (.battery, "221103", "V", 8), (.throttle, "22120F", "V", 0.5),
            (.maf, "221209", "g/s", 1), (.ignition, "22110A", "°", 10),
            (.airFlowVoltage, "221204", "V", 0.5)]
        for (parameter, command, unit, value) in expected {
            XCTAssertEqual(parameter.id, parameter.rawValue)
            XCTAssertEqual(parameter.command, command)
            XCTAssertEqual(parameter.unit, unit)
            let data = parameter.register.width == 2 ? "0064" : "64"
            XCTAssertEqual(try parameter.register.decode("62" + command.dropFirst(2) + data), value, accuracy: 0.0001)
        }
        for error in [DiagnosticError.adapter("NO DATA"), .malformedResponse, .unexpectedResponse, .negativeResponse(0x31), .notInitialized, .busy] {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
    func testCloseDuringInitializationCannotReopenSession() async throws {
        let transport = GateTransport()
        let client = DiagnosticClient(transport: transport)
        let initialize = Task { try await client.initialize() }
        await transport.waitUntilStarted()
        do { try await client.initialize(); XCTFail("Concurrent initialization accepted") } catch {}
        await client.close()
        await transport.release()
        do { try await initialize.value; XCTFail("Closed session initialized") } catch {}
        do { _ = try await client.read(parameter: .rpm); XCTFail() } catch {}
    }
}
actor FixtureTransport: ELMTransport {
    let family: UInt8
    let fallback: Bool
    let failure: String
    var closed = false
    var commands: [String] = []
    init(family: UInt8 = 1, fallback: Bool = false, failure: String = "") {
        self.family = family; self.fallback = fallback; self.failure = failure
    }
    func exchange(_ command: String) async throws -> String {
        commands = commands + [command]
        if command == failure { return "?" }
        switch command {
        case "ATZ": return "ELM327>"
        case "1081": return "5081>"
        case "10C0": return "50C0>"
        case "2183": return fallback ? "NO DATA>" : String(format: "61834142434445%02X>", family)
        case "21FE": return "61FE414243444501>"
        case "17FF00": return "5701012301>"
        case "19020F": return "5902FF01234508>"
        default: return "OK>"
        }
    }
    func close() async { closed = true }
}
actor GateTransport: ELMTransport {
    var continuation: CheckedContinuation<String, Never>?
    var observer: CheckedContinuation<Void, Never>?
    func exchange(_ command: String) async throws -> String {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer?.resume(); observer = nil
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { continuation?.resume(returning: "ELM327>"); continuation = nil }
    func close() async {}
}
