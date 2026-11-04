import Foundation

actor OBDCommandQueue {
    private let transport: OBDTransporting
    private var pendingContinuation: CheckedContinuation<String, Error>?
    private var pendingRequestID: UUID?
    private var timeoutTask: Task<Void, Never>?

    init(transport: OBDTransporting) {
        self.transport = transport
    }

    func handleResponse(_ response: String) {
        completePending(with: .success(response))
    }

    func handleError(_ error: Error) {
        completePending(with: .failure(error))
    }

    func cancelPending() {
        completePending(with: .failure(CancellationError()))
    }

    /// Allow an in-flight generic request to finish before changing protocol sessions.
    func waitUntilIdle(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while pendingContinuation != nil {
            try Task.checkCancellation()
            guard Date() < deadline else { throw AppError.commandInProgress }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func send(_ command: String, timeout: TimeInterval) async throws -> String {
        try Task.checkCancellation()
        guard pendingContinuation == nil else { throw AppError.commandInProgress }
        guard timeout.isFinite, timeout > 0 else { throw AppError.timeout(command) }
        let requestID = UUID()

        // Keep an in-flight request alive when its caller is cancelled. ELM has
        // no response IDs, so session changes must drain the reply before reuse.
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
            pendingRequestID = requestID
            timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(timeout))
                } catch {
                    return
                }
                await self?.timeoutIfStillPending(requestID: requestID, command: command)
            }
            transport.send(command) { [weak self] result in
                if case .failure(let error) = result {
                    Task { await self?.handleSendError(error, requestID: requestID) }
                }
            }
        }
    }

    private func handleSendError(_ error: Error, requestID: UUID) {
        guard pendingRequestID == requestID else { return }
        completePending(with: .failure(error))
    }

    private func timeoutIfStillPending(requestID: UUID, command: String) {
        guard pendingRequestID == requestID else { return }
        completePending(with: .failure(AppError.timeout(command)))
        // ELM replies carry no request identity. Close the connection so a late
        // reply cannot be mistaken for the next command's response.
        transport.disconnect()
    }

    private func completePending(with result: Result<String, Error>) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingRequestID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result)
    }
}
