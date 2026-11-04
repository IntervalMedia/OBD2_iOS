import XCTest
@testable import OBDCore

final class OBDParserTests: XCTestCase {
    func testLiveValuesTolerateEchoAndAdapterNoise() {
        XCTAssertEqual(OBDParser.parseRPM("010C\rSEARCHING...\r41 0C 1A F8\r>"), 1726)
        XCTAssertEqual(OBDParser.parseSpeed("010D\r41 0D 64\r>"), 100)
        XCTAssertEqual(OBDParser.parseCoolantTemp("41 05 7B"), 83)
        XCTAssertEqual(OBDParser.parseThrottlePosition("41 11 FF"), 100)
        XCTAssertEqual(OBDParser.parseBatteryVoltage(" 12.6V\r\n"), 12.6)
    }

    func testRPMRetainsQuarterRevolutionResolution() {
        XCTAssertEqual(OBDParser.parseRPM("410C0005"), 1.25)
    }

    func testMissingMalformedAndTruncatedValuesAreAbsent() {
        for response in ["NO DATA", "?", "410C01", "410CXX00", "410D42"] {
            XCTAssertNil(OBDParser.parseRPM(response), response)
        }
        XCTAssertNil(OBDParser.parseSpeed("410DXX"))
        XCTAssertNil(OBDParser.parseCoolantTemp("4105"))
        XCTAssertNil(OBDParser.parseThrottlePosition("4111ZZ"))
        XCTAssertNil(OBDParser.parseBatteryVoltage("NO DATA"))
    }

    func testTroubleCodesDecodeAllFamiliesAndHexDigits() {
        let codes = OBDParser.parseStoredDTCs("03\r43 01 23 41 00 81 AB C1 EF 00 00\r>")
        XCTAssertEqual(codes.map(\.code), ["P0123", "C0100", "B01AB", "U01EF"])
    }

    func testVINExtractsPrintablePayloadAndSkipsSequenceByte() {
        XCTAssertEqual(
            OBDParser.parseVIN("0902\r490201314E34414C334150304443313233343536>"),
            "1N4AL3AP0DC123456"
        )
        XCTAssertNil(OBDParser.parseVIN("NO DATA"))
    }
}
