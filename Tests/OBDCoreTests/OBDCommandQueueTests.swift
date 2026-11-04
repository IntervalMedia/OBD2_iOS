import Foundation
import XCTest
@testable import OBDCore

final class OBDCommandQueueTests: XCTestCase {
    func testPreviousTimeoutDoesNotFailRepeatedCommand() async throws {
        let transport = QueueTestTransport()
        let queue = OBDCommandQueue(transport: transport)
        let first = Task { try await queue.send("010C", timeout: 0.05) }
        await transport.waitForSends(1)
        transport.completeSend(0, with: .success(()))
        await queue.handleResponse("first")
        _ = try await first.value

        let second = Task { try await queue.send("010C", timeout: 2) }
        await transport.waitForSends(2)
        transport.completeSend(1, with: .success(()))
        try await Task.sleep(nanoseconds: 120_000_000)
        await queue.handleResponse("second")
        let response = try await second.value
        XCTAssertEqual(response, "second")
        XCTAssertEqual(transport.disconnectCount, 0)
    }

    func testPreviousSendFailureDoesNotFailNextCommand() async throws {
        let transport = QueueTestTransport()
        let queue = OBDCommandQueue(transport: transport)
        let first = Task { try await queue.send("010C", timeout: 2) }
        await transport.waitForSends(1)
        await queue.handleResponse("first")
        _ = try await first.value
        let second = Task { try await queue.send("010D", timeout: 2) }
        await transport.waitForSends(2)
        transport.completeSend(0, with: .failure(AppError.notConnected))
        try await Task.sleep(nanoseconds: 30_000_000)
        await queue.handleResponse("second")
        let response = try await second.value
        XCTAssertEqual(response, "second")
    }

    func testCancelPendingResumesWaitingCommandAndAllowsNextCommand() async throws {
        let transport = QueueTestTransport()
        let queue = OBDCommandQueue(transport: transport)
        let pending = Task { try await queue.send("010C", timeout: 2) }
        await transport.waitForSends(1)
        await queue.cancelPending()
        do {
            _ = try await pending.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
        try await queue.waitUntilIdle(timeout: 0.1)
        let next = Task { try await queue.send("010D", timeout: 2) }
        await transport.waitForSends(2)
        await queue.handleResponse("next")
        let response = try await next.value
        XCTAssertEqual(response, "next")
    }

    func testTimeoutDisconnectsTransportAndReleasesQueue() async throws {
        let transport = QueueTestTransport()
        let queue = OBDCommandQueue(transport: transport)
        let pending = Task { try await queue.send("010C", timeout: 0.02) }
        await transport.waitForSends(1)
        transport.completeSend(0, with: .success(()))
        do {
            _ = try await pending.value
            XCTFail("Expected timeout")
        } catch AppError.timeout(let command) {
            XCTAssertEqual(command, "010C")
        }
        XCTAssertEqual(transport.disconnectCount, 1)
        try await queue.waitUntilIdle(timeout: 0.1)
    }

    func testCancelledCallerDrainsResponseBeforeQueueReuse() async throws {
        let transport = QueueTestTransport()
        let queue = OBDCommandQueue(transport: transport)
        let pending = Task { try await queue.send("010C", timeout: 2) }
        await transport.waitForSends(1)
        pending.cancel()
        do {
            try await queue.waitUntilIdle(timeout: 0.02)
            XCTFail("Cancelled caller must still drain the in-flight reply")
        } catch AppError.commandInProgress {
        }
        await queue.handleResponse("drained")
        let response = try await pending.value
        XCTAssertEqual(response, "drained")
        try await queue.waitUntilIdle(timeout: 0.1)
    }

    func testMissingSendCompletionStillTimesOut() async throws {
        let transport = QueueTestTransport()
        let queue = OBDCommandQueue(transport: transport)
        do {
            _ = try await queue.send("010C", timeout: 0.02)
            XCTFail("Expected timeout even when transport never calls its completion")
        } catch AppError.timeout(let command) {
            XCTAssertEqual(command, "010C")
        }
        XCTAssertEqual(transport.disconnectCount, 1)
    }

    func testWaitUntilIdleHasBoundedTimeout() async throws {
        let transport = QueueTestTransport()
        let queue = OBDCommandQueue(transport: transport)
        let pending = Task { try await queue.send("010C", timeout: 2) }
        await transport.waitForSends(1)
        do {
            try await queue.waitUntilIdle(timeout: 0.01)
            XCTFail("Expected busy queue timeout")
        } catch AppError.commandInProgress {
        }
        await queue.cancelPending()
        _ = try? await pending.value
    }
}

private final class QueueTestTransport: OBDTransporting {
    var onStateChanged: ((OBDTransportState) -> Void)?
    var onResponse: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    private let lock = NSLock()
    private var completions: [(Result<Void, Error>) -> Void] = []
    private var disconnections = 0

    var disconnectCount: Int { lock.withLock { disconnections } }
    func connect() {}
    func disconnect() { lock.withLock { disconnections += 1 } }
    func send(_ command: String, completion: @escaping (Result<Void, Error>) -> Void) {
        lock.withLock { completions.append(completion) }
    }
    func completeSend(_ index: Int, with result: Result<Void, Error>) {
        let completion = lock.withLock { completions[index] }
        completion(result)
    }
    func waitForSends(_ count: Int) async {
        for _ in 0..<1_000 {
            if lock.withLock({ completions.count >= count }) { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Command was never sent")
    }
}
