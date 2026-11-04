import XCTest
@testable import OBDCore

final class AdapterResponseBufferTests: XCTestCase {
    func testPartialAndCombinedResponsesPreserveCommandBoundaries() {
        let buffer = AdapterResponseBuffer()
        XCTAssertEqual(buffer.append(Data("41 0C 1A".utf8)), [])
        XCTAssertEqual(buffer.append(Data(" F8\r>41 0D 64\r>41 05".utf8)), ["41 0C 1A F8", "41 0D 64"])
        XCTAssertEqual(buffer.append(Data(" 7B\r>".utf8)), ["41 05 7B"])
    }

    func testClearDiscardsIncompletePriorSessionAndIgnoresEmptyPrompts() {
        let buffer = AdapterResponseBuffer()
        _ = buffer.append(Data("stale".utf8))
        buffer.clear()
        XCTAssertEqual(buffer.append(Data(">\r>OK\r>".utf8)), ["OK"])
    }
}
