import XCTest
@testable import NissanCore

final class ProtocolTests: XCTestCase {
    func testEnhancedReadAndBigEndianConversion() throws {
        let register = Register(id: 0x1234, width: 2, scale: 0.125, offset: 0)
        XCTAssertEqual(register.command, "221234")
        XCTAssertEqual(try register.decode("221234\r62 12 34 1F 40\r>"), 1000)
    }
    func testOneByteOffset() throws {
        XCTAssertEqual(try Register(id: 0x1101, width: 1, scale: 1, offset: -50).decode("62110182\r>"), 80)
    }
    func testRejectWrongRegisterMalformedAndTruncatedReplies() {
        let register = Register(id: 0x1234, width: 2, scale: 1, offset: 0)
        for reply in ["6212350100>", "62123401>", "621234XX00>", "NO DATA>", "STOPPED>", "7F2231>", "?"] {
            XCTAssertThrowsError(try register.decode(reply), reply)
        }
    }
    func testRejectAmbiguousECUAndUnexpectedLength() {
        let register = Register(id: 0x1234, width: 1, scale: 1, offset: 0)
        XCTAssertThrowsError(try register.decode("62123401\r62123402>"))
        XCTAssertThrowsError(try register.decode("6212340102>"))
    }
    func testInitializationAndRead() async throws {
        let transport = ScriptedTransport()
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        _ = try await client.read(parameter: .rpm)
        let commands = await transport.commands
        XCTAssertEqual(Array(commands.prefix(3)), ["ATZ", "ATE0", "ATL0"])
        XCTAssertTrue(commands.contains("ATSP6"))
        XCTAssertEqual(commands.last, NissanParameter.rpm.command)
    }
    func testReadRequiresInitialization() async {
        let client = DiagnosticClient(transport: ScriptedTransport())
        do { _ = try await client.read(parameter: .rpm); XCTFail("Read before initialization") } catch {}
    }
    func testAdapterFailureStopsInitialization() async {
        let client = DiagnosticClient(transport: ScriptedTransport(fail: true))
        do { try await client.initialize(); XCTFail("Unsupported adapter accepted") } catch {}
    }
}
actor ScriptedTransport: ELMTransport {
    var commands: [String] = []
    let fail: Bool
    init(fail: Bool = false) { self.fail = fail }
    func exchange(_ command: String) async throws -> String {
        commands = commands + [command]
        if fail { return "?\r>" }
        if command == "ATZ" { return "ELM327 v1.5\r>" }
        if command.hasPrefix("10") { return "50" + command.dropFirst(2) + "\r>" }
        if command.hasPrefix("AT") { return "OK\r>" }
        return "62" + command.dropFirst(2) + String(repeating: "00", count: NissanParameter.rpm.register.width) + "\r>"
    }
    func close() async {}
}
