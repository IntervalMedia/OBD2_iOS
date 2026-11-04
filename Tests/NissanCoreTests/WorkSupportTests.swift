import XCTest
@testable import NissanCore

final class WorkSupportTests: XCTestCase {
    func testMasksValidateServiceAndBaseAndExcludeContinuation() throws {
        XCTAssertEqual(try NissanWorkSupportCapabilities.decodeMask("710034000001", service: 0x31, base: 0), [3, 4, 6])
        XCTAssertEqual(try NissanWorkSupportCapabilities.decodeMask("702080000002", service: 0x30, base: 0x20), [0x21, 0x3F])
        for reply in ["710034", "700034000000", "712034000000", "7F3131"] {
            XCTAssertThrowsError(try NissanWorkSupportCapabilities.decodeMask(reply, service: 0x31, base: 0))
        }
    }

    func testDiscoveryAndSingleStartFuelTrimReset() async throws {
        let transport = WorkSupportFixture()
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        let capabilities = try await client.discoverWorkSupport()
        XCTAssertEqual(capabilities.learnings, [3, 4, 6])
        XCTAssertEqual(capabilities.corrections, [1, 2])
        try await client.performLearning(.fuelTrimReset)
        let commands = await transport.commands
        XCTAssertTrue(commands.contains("ATCRA7E8"))
        XCTAssertEqual(commands.filter { $0 == "310600" }.count, 1)
        XCTAssertEqual(Array(commands.suffix(4)), ["10C0", "310600", "320600", "310601"])
    }

    func testIdleLearningKeepsSessionAliveThenVerifiesResult() async throws {
        let transport = WorkSupportFixture()
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        _ = try await client.discoverWorkSupport()
        try await client.performLearning(.idleAirVolume)
        let commands = await transport.commands
        XCTAssertEqual(commands.filter { $0 == "310300" }.count, 1)
        XCTAssertEqual(commands.filter { $0 == "3E01" }.count, 20)
        XCTAssertEqual(Array(commands.suffix(2)), ["320300", "310301"])
    }

    func testUnsupportedAndUndiscoveredNeverWrite() async throws {
        let transport = WorkSupportFixture(mask: "710000000000")
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        do { try await client.performLearning(.fuelTrimReset); XCTFail() } catch {}
        _ = try await client.discoverWorkSupport()
        do { try await client.performLearning(.fuelTrimReset); XCTFail() } catch {}
        let commands = await transport.commands
        XCTAssertFalse(commands.contains("310600"))
    }

    func testFailedCompletionClosesAndCannotRetry() async throws {
        let transport = WorkSupportFixture(final: "710601")
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        _ = try await client.discoverWorkSupport()
        do { try await client.performLearning(.fuelTrimReset); XCTFail() } catch {}
        do { try await client.performLearning(.fuelTrimReset); XCTFail() } catch {}
        let closed = await transport.closed
        let commands = await transport.commands
        XCTAssertTrue(closed)
        XCTAssertEqual(commands.filter { $0 == "310600" }.count, 1)
    }

    func testCancellationAfterStartClosesWithoutFurtherWrites() async throws {
        let started = expectation(description: "Start sent")
        let transport = WorkSupportFixture(started: started)
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        _ = try await client.discoverWorkSupport()
        let task = Task { try await client.performLearning(.fuelTrimReset) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
        let commands = await transport.commands
        let closed = await transport.closed
        XCTAssertTrue(closed)
        XCTAssertEqual(commands.last, "310600")
    }

    func testPendingStopDoesNotResendStart() async throws {
        let transport = WorkSupportFixture(pendingStop: true)
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        _ = try await client.discoverWorkSupport()
        try await client.performLearning(.fuelTrimReset)
        let commands = await transport.commands
        XCTAssertEqual(commands.filter { $0 == "310600" }.count, 1)
        XCTAssertEqual(commands.filter { $0 == "320600" }.count, 2)
    }

    func testDieselDiscoveryRejectedWithoutRequests() async throws {
        let transport = WorkSupportFixture()
        let client = DiagnosticClient(transport: transport, profile: .diesel)
        try await client.initialize()
        do { _ = try await client.discoverWorkSupport(); XCTFail() } catch {}
        let commands = await transport.commands
        XCTAssertFalse(commands.contains("3100"))
    }
}

private actor WorkSupportFixture: ELMTransport {
    var commands: [String] = []
    var closed = false
    let mask: String
    let final: String
    let started: XCTestExpectation?
    var pendingStop: Bool
    init(mask: String = "710034000000", final: String = "710602", started: XCTestExpectation? = nil, pendingStop: Bool = false) {
        self.mask = mask; self.final = final; self.started = started; self.pendingStop = pendingStop
    }
    func exchange(_ command: String) async throws -> String {
        commands.append(command)
        switch command {
        case "ATZ": return "ELM327"
        case "1081": return "5081"
        case "10C0": return "50C0"
        case "3000", "3020", "3040", "3060": return "70" + command.suffix(2) + "80000000"
        case "3100": return mask
        case "3B00": return "7B00C0000000"
        case "310600":
            if let started { started.fulfill(); try await Task.sleep(for: .seconds(60)) }
            return "710600"
        case "320600":
            if pendingStop { pendingStop = false; return "7F3278" }
            return "720600"
        case "310601": return final
        case "310300": return "710300"
        case "320300": return "720300"
        case "310301": return "710302"
        case "3E01": return "7E01"
        default: return "OK"
        }
    }
    func close() async { closed = true }
}
