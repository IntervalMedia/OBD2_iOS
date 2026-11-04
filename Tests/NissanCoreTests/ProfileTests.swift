import XCTest
@testable import NissanCore

final class ProfileTests: XCTestCase {
    func testDieselUsesRecoveredRegistersAndScaling() throws {
        let examples: [(NissanParameter, String, String, Double)] = [
            (.rpm, "221201", "6212012710", 976.950004696846),
            (.battery, "221105", "621105A0", 12.8),
            (.coolant, "221101", "6211017B", 83),
            (.speed, "221102", "62110232", 100),
            (.airFlowVoltage, "221205", "6212050064", 0.5)
        ]
        for (parameter, command, response, expected) in examples {
            let register = try NissanECUProfile.diesel.register(for: parameter)
            XCTAssertEqual(register.command, command)
            XCTAssertEqual(try register.decode(response), expected, accuracy: 0.0001)
        }
        for parameter in [NissanParameter.intakeAir, .throttle, .maf, .ignition] {
            XCTAssertThrowsError(try NissanECUProfile.diesel.register(for: parameter)) { error in
                XCTAssertEqual(error as? DiagnosticError, .unsupportedParameter(parameter.rawValue))
            }
        }
    }

    func testSupportedRegisterBitmapRejectsOverflowAndAcceptsEmptySupport() throws {
        XCTAssertEqual(try SupportedRegisters.decode(response: "62110000000000", base: 0x1100), [])
        XCTAssertThrowsError(try SupportedRegisters.decode(response: "62FFF080000000", base: 0xFFF0))
    }

    func testEmptyLoggingSelectionDoesNotInitializeOrWrite() async throws {
        let transport = FixtureTransport()
        let client = DiagnosticClient(transport: transport)
        let stream = try await NissanDataLogger(client: client).stream(parameters: [])
        for try await _ in stream { XCTFail("Empty selection produced a sample") }
        let commands = await transport.commands
        XCTAssertTrue(commands.isEmpty)
    }

    func testRegisterRejectsUnsupportedWidthsAndOutOfSequenceFrameNumbers() {
        XCTAssertThrowsError(try Register(id: 0x1101, width: 3, scale: 1, offset: 0).decode("621101000000"))
        XCTAssertThrowsError(try ELMPayload.decode(response: "008\r0:618341424344\rZ:4501>", command: "2183"))
    }
}
