import XCTest
@testable import NissanCore

final class CommunicationTests: XCTestCase {
    func testBitmapRegistersAndMismatchRejection() throws {
        XCTAssertEqual(try SupportedRegisters.decode(response: "62110080000001>", base: 0x1100), [0x1101, 0x1120])
        XCTAssertThrowsError(try SupportedRegisters.decode(response: "62112080000001>", base: 0x1100))
        XCTAssertThrowsError(try SupportedRegisters.decode(response: "62110080>", base: 0x1100))
    }
    func testBoundedLoggerCanBeCancelledWithoutClearing() async throws {
        let transport = CommunicationFixture()
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        let logger = NissanDataLogger(client: client)
        let firstCycle = expectation(description: "First logging cycle")
        let consumer = Task {
            let stream = try await logger.stream(parameters: [.battery], cycleDelay: .milliseconds(10))
            var first = true
            for try await samples in stream {
                if first { XCTAssertEqual(samples.first?.value ?? 0, 12.8, accuracy: 0.001); firstCycle.fulfill(); first = false }
            }
        }
        await fulfillment(of: [firstCycle], timeout: 2)
        consumer.cancel()
        try await consumer.value
        let commands = await transport.commands
        XCTAssertFalse(commands.contains(where: { $0.hasPrefix("14") }))
    }
    func testDTCServiceSelectionMatchesAndroid() {
        for (profile, family, read, clear) in [
            (NissanECUProfile.petrol, UInt8(1), "17FF00", "14FF00"),
            (.petrol, 0xA0, "19020F", "14FFFFFF"),
            (.diesel, 1, "1902FF", "14FFFFFF"),
            (.diesel, 5, "19022F", "14FFFFFF"),
            (.diesel, 0x70, "19020F", "14FFFFFF")
        ] {
            XCTAssertEqual(profile.readDTCCommand(family: family), read)
            XCTAssertEqual(profile.clearDTCCommand(family: family), clear)
        }
    }
    func testClearEntersSessionBeforeOneWriteAndValidatesReply() async throws {
        let transport = CommunicationFixture()
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        _ = try await client.identifyECU()
        try await client.clearTroubleCodes()
        let commands = await transport.commands
        XCTAssertEqual(Array(commands.suffix(2)), ["10C0", "14FF00"])
        XCTAssertEqual(commands.filter { $0 == "14FF00" }.count, 1)
    }
    func testClearNegativeResponseIsNotSuccessAndIsNotRetried() async throws {
        let transport = CommunicationFixture(clearResponse: "7F1422>")
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        _ = try await client.identifyECU()
        do { try await client.clearTroubleCodes(); XCTFail() }
        catch { XCTAssertEqual(error as? DiagnosticError, .negativeResponse(0x22)) }
        let commands = await transport.commands
        XCTAssertEqual(commands.filter { $0 == "14FF00" }.count, 1)
    }
    func testDTCReadEntersSession() async throws {
        let transport = CommunicationFixture()
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        _ = try await client.identifyECU()
        let codes = try await client.readTroubleCodes()
        XCTAssertTrue(codes.isEmpty)
        let commands = await transport.commands
        XCTAssertEqual(Array(commands.suffix(2)), ["10C0", "17FF00"])
    }
    func testLoggingCycleReadsInOrderWithSeparateFailures() async throws {
        let transport = CommunicationFixture()
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        let cycle = try await client.readCycle(parameters: [.battery, .coolant])
        XCTAssertEqual(cycle.count, 2)
        XCTAssertEqual(cycle[0].parameter, .battery)
        XCTAssertEqual(cycle[0].value ?? 0, 12.8, accuracy: 0.001)
        XCTAssertNil(cycle[1].value)
        XCTAssertNotNil(cycle[1].error)
    }
    func testDieselMappingNeverUsesPetrolRegisterByAccident() async throws {
        let transport = CommunicationFixture()
        let client = DiagnosticClient(transport: transport, profile: .diesel)
        try await client.initialize()
        let voltage = try await client.read(parameter: .battery)
        XCTAssertEqual(voltage, 12.8, accuracy: 0.001)
        do { _ = try await client.read(parameter: .maf); XCTFail() } catch {}
        let commands = await transport.commands
        XCTAssertTrue(commands.contains("221105"))
        XCTAssertFalse(commands.contains("221209"))
    }
}
actor CommunicationFixture: ELMTransport {
    let clearResponse: String
    var commands: [String] = []
    init(clearResponse: String = "54>") { self.clearResponse = clearResponse }
    func exchange(_ command: String) async throws -> String {
        commands = commands + [command]
        switch command {
        case "ATZ": return "ELM327>"
        case "1081": return "5081>"
        case "10C0": return "50C0>"
        case "2183": return "6183414243444501>"
        case "14FF00", "14FFFFFF": return clearResponse
        case "17FF00": return "5700>"
        case "221103": return "621103A0>"
        case "221105": return "621105A0>"
        case "221101": return "7F2231>"
        default: return "OK>"
        }
    }
    func close() async {}
}

final class LoggingDrainTests: XCTestCase {
    func testCancelDuringReadDrainsBeforeDTCWithoutCancellingTransport() async throws {
        let transport = DrainFixture()
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        _ = try await client.identifyECU()
        let consumer = Task {
            let stream = try await NissanDataLogger(client: client).stream(parameters: [.battery, .coolant])
            for try await _ in stream {}
        }
        await transport.waitForRead()
        consumer.cancel()
        let clear = Task { try await client.clearTroubleCodes() }
        await transport.releaseRead()
        try await consumer.value
        try await clear.value
        let commands = await transport.commands
        XCTAssertEqual(Array(commands.suffix(3)), ["221103", "10C0", "14FF00"])
        let cancellations = await transport.cancellations
        XCTAssertEqual(cancellations, 0)
    }
}
actor DrainFixture: ELMTransport {
    var commands: [String] = []
    var cancellations = 0
    private var read: CheckedContinuation<String, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func exchange(_ command: String) async throws -> String {
        commands = commands + [command]
        switch command {
        case "ATZ": return "ELM327>"
        case "1081": return "5081>"
        case "10C0": return "50C0>"
        case "2183": return "6183414243444501>"
        case "14FF00": return "54>"
        case "221103":
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    read = continuation
                    observer?.resume(); observer = nil
                }
            } onCancel: { Task { await self.recordCancellation() } }
        default: return "OK>"
        }
    }
    func recordCancellation() { cancellations += 1 }
    func waitForRead() async {
        if read != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func releaseRead() { read?.resume(returning: "621103A0>"); read = nil }
    func close() async {}
}
