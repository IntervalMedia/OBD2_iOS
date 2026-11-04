import XCTest
@testable import OBDCore

final class ConnectionSetupTests: XCTestCase {
    func testInitializationRequiresRealAcknowledgments() throws {
        XCTAssertNoThrow(try AdapterSetupResponse.validate("ATZ\rELM327 v1.5\r>", command: "ATZ"))
        XCTAssertNoThrow(try AdapterSetupResponse.validate("ATE0\rOK\r>", command: "ATE0"))
        for response in ["?", "NO DATA", "NOT OK", "", "OK\rERROR"] {
            XCTAssertThrowsError(try AdapterSetupResponse.validate(response, command: "ATE0"))
        }
        XCTAssertThrowsError(try AdapterSetupResponse.validate("OK", command: "ATZ"))
    }

    func testVehicleProbeRequiresCompleteMatchingPayload() throws {
        for response in ["0100\rSEARCHING...\r41 00 BE 3E B8 13>", "410000000000\r4100FFFFFFFF>"] {
            XCTAssertNoThrow(try AdapterSetupResponse.validate(response, command: "0100"))
        }
        for response in ["NO DATA", "4100", "4100GG000000", "410C00000000", "OK", "410000000000\rCAN ERROR"] {
            XCTAssertThrowsError(try AdapterSetupResponse.validate(response, command: "0100"))
        }
    }

    func testDiagnosticResponsesRejectNoiseAndMismatchedService() {
        XCTAssertTrue(AdapterSetupResponse.isDiagnosticResponse("03\r43 00 00>", service: "43"))
        XCTAssertTrue(AdapterSetupResponse.isDiagnosticResponse("44>", service: "44"))
        for response in ["NO DATA", "OK", "4301", "43ZZZZ", "410000000000", "430000\rERROR"] {
            XCTAssertFalse(AdapterSetupResponse.isDiagnosticResponse(response, service: "43"))
        }
        XCTAssertFalse(AdapterSetupResponse.isDiagnosticResponse("4400>", service: "44"))
    }
}
