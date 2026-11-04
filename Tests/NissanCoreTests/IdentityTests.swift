import XCTest
@testable import NissanCore

final class IdentityTests: XCTestCase {
    func testNegativeServicePatternInsideMultilineDataIsNotAnECURejection() throws {
        XCTAssertEqual(try ELMPayload.decode(response: "009\r0:5902FF012345\r1:7F1422>", command: "19020F"), [0x59, 2, 0xFF, 1, 0x23, 0x45, 0x7F, 0x14, 0x22])
    }
    func testIdentityAndNumberedPayload() throws {
        let identity = try ECUIdentity(response: "2183\r008\r0:618341424344\r1:4501\r>", command: "2183")
        XCTAssertEqual(identity.identifier, "ABCDE")
        XCTAssertEqual(identity.family, 1)
        XCTAssertEqual(try ECUIdentity(response: "61FE4142434445A00102>", command: "21FE").family, 0xA0)
    }
    func testRejectMalformedIdentityAndMultiline() {
        for response in ["008\r0:618341424344\r2:4501>", "009\r0:618341424344\r1:4501>",
                         "008\r0:618341424344\r1:4501\r1:4501>", "61834142434401>",
                         "61FE414243444501>", "618341424344FF01>"] {
            XCTAssertThrowsError(try ECUIdentity(response: response, command: "2183"), response)
        }
    }
    func testLegacyAndUDSTroubleCodes() throws {
        let legacy = try TroubleCode.decode(response: "5702012301C10080>", command: "17FF00")
        XCTAssertEqual(legacy.map(\.code), ["P0123", "U0100"])
        XCTAssertEqual(legacy[1].rawRecord, [0xC1, 0, 0x80])
        XCTAssertEqual(legacy[1].status, 0x80)
        let uds = try TroubleCode.decode(response: "5902FF01234508>", command: "19020F")
        XCTAssertEqual(uds.first?.code, "P0123")
        XCTAssertEqual(uds.first?.rawRecord, [1, 0x23, 0x45, 8])
        XCTAssertEqual(try TroubleCode.decode(response: "5700>", command: "17FF00"), [])
        XCTAssertEqual(try TroubleCode.decode(response: "5902FF>", command: "19020F"), [])
    }
    func testRejectInvalidDTCRecords() {
        for response in ["5702012301>", "5700012301>", "5902FF012345>", "5901FF01234508>", "7F1931>"] {
            XCTAssertThrowsError(try TroubleCode.decode(response: response, command: response.hasPrefix("57") ? "17FF00" : "19020F"))
        }
    }
}
