import XCTest
import Network
@testable import OBDCore

final class OBDTransportTests: XCTestCase {
    func testWiFiRouteIsRequired() {
        XCTAssertEqual(OBDTransport.parameters().requiredInterfaceType, .wifi)
    }

    func testOldReceiveCannotDeliverIntoNewConnection() async {
        let first = FakeWiFiConnection()
        let second = FakeWiFiConnection()
        var connections = [first, second]
        let transport = OBDTransport(host: "192.168.0.10", port: 35000) { _, _ in connections.removeFirst() }
        let ready = expectation(description: "ready")
        ready.expectedFulfillmentCount = 2
        transport.onStateChanged = { if $0.isConnected { ready.fulfill() } }
        transport.connect()
        await first.waitForReceive()
        let oldReceive = first.receiver
        transport.connect()
        await fulfillment(of: [ready], timeout: 2)
        await second.waitForReceive()
        let received = expectation(description: "new response")
        transport.onResponse = { response in XCTAssertEqual(response, "NEW"); received.fulfill() }
        oldReceive?(Data("OLD>".utf8), false, nil)
        second.receiver?(Data("NEW>".utf8), false, nil)
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(first.cancelCount, 1)
        transport.disconnect()
    }

    func testEOFReportsErrorAndClosesSocketWithoutReceivingAgain() async {
        let connection = FakeWiFiConnection()
        let transport = OBDTransport(host: "192.168.0.10", port: 35000) { _, _ in connection }
        let failed = expectation(description: "EOF error")
        transport.onError = { _ in failed.fulfill() }
        transport.connect()
        await connection.waitForReceive()
        connection.receiver?(nil, true, nil)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(connection.receiveCount, 1)
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testInvalidEndpointDoesNotCreateSocket() async {
        let transport = OBDTransport(host: "", port: 0) { _, _ in
            XCTFail("Invalid endpoint must not create a socket")
            return FakeWiFiConnection()
        }
        let failed = expectation(description: "invalid endpoint")
        transport.onError = { _ in failed.fulfill() }
        transport.connect()
        await fulfillment(of: [failed], timeout: 2)
    }

    func testReceiveFailureDoesNotRestartReadLoop() async {
        let connection = FakeWiFiConnection()
        let transport = OBDTransport(host: "192.168.0.10", port: 35000) { _, _ in connection }
        let failed = expectation(description: "read failure")
        transport.onError = { _ in failed.fulfill() }
        transport.connect()
        await connection.waitForReceive()
        connection.receiver?(nil, false, AppError.notConnected)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(connection.receiveCount, 1)
        XCTAssertEqual(connection.cancelCount, 1)
        let rejected = expectation(description: "send rejected")
        transport.send("0100") { result in
            if case .success = result { XCTFail("Closed socket accepted a command") }
            rejected.fulfill()
        }
        await fulfillment(of: [rejected], timeout: 2)
    }

}

private final class FakeWiFiConnection: AdapterTCPConnection {
    var stateUpdateHandler: ((NWConnection.State) -> Void)?
    private let lock = NSLock()
    private var storedReceiver: ((Data?, Bool, Error?) -> Void)?
    private var reads = 0
    private var cancellations = 0
    var receiver: ((Data?, Bool, Error?) -> Void)? { lock.withLock { storedReceiver } }
    var receiveCount: Int { lock.withLock { reads } }
    var cancelCount: Int { lock.withLock { cancellations } }
    func start(queue: DispatchQueue) { stateUpdateHandler?(.ready) }
    func cancel() { lock.withLock { cancellations += 1 } }
    func send(_ data: Data, completion: @escaping (Error?) -> Void) { completion(nil) }
    func receive(_ completion: @escaping (Data?, Bool, Error?) -> Void) {
        lock.withLock { reads += 1; storedReceiver = completion }
    }
    func waitForReceive() async {
        for _ in 0..<200 where receiver == nil { try? await Task.sleep(for: .milliseconds(5)) }
    }
}
