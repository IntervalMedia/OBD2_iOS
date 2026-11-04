import Foundation
import Network
import NissanCore

/// Wi-Fi ELM327 transport. DiagnosticClient serializes exchanges.
final class TCPTransport: ELMTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "NissanDiagnostics.ELM")
    private var connection: NWConnection?
    private var requestID: UUID?
    private var pending: CheckedContinuation<String, Error>?
    private var deadline: DispatchWorkItem?
    private var buffer = Data()
    private var closed = false
    private let host: String
    private let port: UInt16

    init(host: String, port: UInt16) { self.host = host; self.port = port }

    func exchange(_ command: String) async throws -> String {
        try await exchange(command, timeout: 8)
    }

    func exchange(_ command: String, timeout: TimeInterval) async throws -> String {
        try Task.checkCancellation()
        guard timeout.isFinite, timeout > 0, timeout <= 30 else { throw TransportError.invalidRequest }
        guard !command.isEmpty, command.count <= 128, command.allSatisfy({ $0.isASCII && $0 != "\r" && $0 != "\n" }) else { throw TransportError.invalidRequest }
        let id = UUID()
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !cancellation.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                    guard !self.closed else { continuation.resume(throwing: TransportError.closed); return }
                    guard self.pending == nil else { continuation.resume(throwing: TransportError.busy); return }
                    self.pending = continuation
                    self.requestID = id
                    self.buffer.removeAll(keepingCapacity: true)
                    let timeoutTask = DispatchWorkItem { if self.requestID == id { self.fail(TransportError.timeout) } }
                    self.deadline = timeoutTask
                    self.queue.asyncAfter(deadline: .now() + timeout, execute: timeoutTask)
                    if let connection = self.connection { self.send(command, on: connection, id: id) }
                    else {
                        guard let port = NWEndpoint.Port(rawValue: self.port) else { self.fail(TransportError.closed); return }
                        let connection = NWConnection(host: NWEndpoint.Host(self.host), port: port, using: .tcp)
                        self.connection = connection
                        connection.stateUpdateHandler = { state in
                            switch state {
                            case .ready: self.send(command, on: connection, id: id)
                            case .failed(let error): self.fail(error)
                            case .cancelled: self.fail(TransportError.closed)
                            default: break
                            }
                        }
                        connection.start(queue: self.queue)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
            self.queue.async { if self.requestID == id { self.fail(CancellationError()) } }
        }
    }

    private func send(_ command: String, on connection: NWConnection, id: UUID) {
        guard pending != nil, requestID == id else { return }
        connection.send(content: Data((command + "\r").utf8), completion: .contentProcessed { error in
            guard self.requestID == id else { return }
            if let error { self.fail(error) } else { self.receive(on: connection, id: id) }
        })
    }

    private func receive(on connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, ended, error in
            guard self.pending != nil, self.requestID == id else { return }
            if let error { self.fail(error); return }
            if let data { self.buffer.append(data) }
            guard self.buffer.count <= 65_536 else { self.fail(TransportError.responseTooLarge); return }
            if self.buffer.contains(0x3e) {
                let response = String(decoding: self.buffer, as: UTF8.self)
                let continuation = self.pending
                self.pending = nil
                self.requestID = nil
                self.deadline?.cancel()
                continuation?.resume(returning: response)
            } else if ended { self.fail(TransportError.closed) }
            else { self.receive(on: connection, id: id) }
        }
    }

    private func fail(_ error: Error) {
        let continuation = pending
        pending = nil
        requestID = nil
        closed = true
        deadline?.cancel()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        continuation?.resume(throwing: error)
    }

    func close() async { await withCheckedContinuation { done in queue.async { self.fail(TransportError.closed); done.resume() } } }

    enum TransportError: LocalizedError {
        case closed, busy, timeout, responseTooLarge, invalidRequest
        var errorDescription: String? {
            switch self {
            case .closed: "Adapter connection closed. Reconnect to continue."
            case .busy: "An adapter request is already in progress."
            case .timeout: "Adapter did not return a prompt within the request timeout."
            case .invalidRequest: "Invalid adapter command or timeout."
            case .responseTooLarge: "Adapter response exceeded the allowed size."
            }
        }
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
