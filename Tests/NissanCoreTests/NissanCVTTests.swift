import XCTest
@testable import NissanCore

final class NissanCVTTests: XCTestCase {
    func testInformationDecodingUsesExactUnsignedWidths() throws {
        let info = try NissanCVTInformation(identity: "61834142434445", calibration: "6102000100020003000400050006", deterioration: "6103FFFFFFFF", counters: "611000020000000C000009" + String(repeating: "00", count: 15) + "0018")
        XCTAssertEqual(info.identifier, "31036-ABCDE")
        XCTAssertEqual(info.calibrationIDs, ["0001", "0002", "0003", "0004", "0005", "0006"])
        XCTAssertEqual(info.deteriorationCounter, UInt32.max)
        XCTAssertEqual(info.cvtA, 9)
        XCTAssertEqual(info.cvtB, 2)
        XCTAssertEqual(info.highTemperatureCount, 2, accuracy: 0.00001)
        XCTAssertEqual(info.veryHighTemperatureCount, 4, accuracy: 0.00001)
    }

    func testRejectsShortWrongAndNegativeResponses() {
        for identity in ["61834142", "61834142434400", "61844142434445", "7F2131"] {
            XCTAssertThrowsError(try NissanCVTInformation(identity: identity, calibration: "6102000100020003000400050006", deterioration: "610300000001", counters: "6110" + String(repeating: "00", count: 26)))
        }
        XCTAssertThrowsError(try NissanCVTInformation(identity: "61834142434445", calibration: "61020001", deterioration: "610300000001", counters: "6110"))
        XCTAssertThrowsError(try NissanCVTInformation(identity: "61834142434445", calibration: "6102000100020003000400050006", deterioration: "6103000001", counters: "6110"))
    }

    func testReadRequiresInitializationAndUsesOnlyReadCommands() async throws {
        let transport = CVTFixtureTransport()
        let client = NissanCVTClient(transport: transport)
        do { _ = try await client.readInformation(); XCTFail() } catch {}
        try await client.initialize()
        let result = try await client.readInformation()
        XCTAssertEqual(result.deteriorationCounter, 42)
        let commands = await transport.commands
        XCTAssertTrue(commands.contains("ATSH7E1"))
        XCTAssertTrue(commands.contains("ATCRA7E9"))
        XCTAssertEqual(Array(commands.suffix(4)), ["2183", "2102", "2103", "2110"])
        await client.close()
        do { _ = try await client.readInformation(); XCTFail() } catch {}
    }

    func testNoDataUsesBoundedTimingFallback() async throws {
        let transport = CVTFixtureTransport(fallback: true)
        let client = NissanCVTClient(transport: transport)
        try await client.initialize()
        let commands = await transport.commands
        XCTAssertEqual(commands.filter { $0 == "2101" }.count, 3)
        XCTAssertTrue(commands.contains("ATST64"))
        XCTAssertTrue(commands.contains("ATAT0"))
    }

    func testUnsupportedVariantAndInitializationFailuresCloseTransport() async {
        for failure in ["ATZ", "ATCRA7E9", "10C0", "2101"] {
            let transport = CVTFixtureTransport(failure: failure)
            let client = NissanCVTClient(transport: transport)
            do { try await client.initialize(); XCTFail(failure) } catch {}
            let closed = await transport.closed
            XCTAssertTrue(closed)
        }
    }

    func testCloseDuringInitializeCannotReopenSession() async throws {
        let transport = GateTransport()
        let client = NissanCVTClient(transport: transport)
        let task = Task { try await client.initialize() }
        await transport.waitUntilStarted()
        do { try await client.initialize(); XCTFail() } catch {}
        await client.close()
        await transport.release()
        do { try await task.value; XCTFail() } catch {}
        do { _ = try await client.readInformation(); XCTFail() } catch {}
    }
}

private actor CVTFixtureTransport: ELMTransport {
    let fallback: Bool
    let failure: String
    var commands: [String] = []
    var closed = false
    init(fallback: Bool = false, failure: String = "") { self.fallback = fallback; self.failure = failure }
    func exchange(_ command: String) async throws -> String {
        commands += [command]
        if command == failure { return "?" }
        switch command {
        case "ATZ": return "ELM327>"
        case "10C0": return "50C0>"
        case "2101": return fallback && commands.filter({ $0 == "2101" }).count <= 2 ? "NO DATA>" : "610100>"
        case "2183": return "61834142434445>"
        case "2102": return "6102000100020003000400050006>"
        case "2103": return "61030000002A>"
        case "2110": return "6110" + String(repeating: "00", count: 26) + ">"
        default: return "OK>"
        }
    }
    func close() async { closed = true }
}
