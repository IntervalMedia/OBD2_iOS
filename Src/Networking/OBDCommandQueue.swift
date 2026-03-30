import Foundation

actor OBDCommandQueue {
    private let transport: OBDTransporting
    private var pendingContinuation: CheckedContinuation<String, Error>?
    private var pendingCommand: String?

    init(transport: OBDTransporting) {
        self.transport = transport
    }

    func handleResponse(_ response: String) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingCommand = nil
        continuation.resume(returning: response)
    }

    func handleError(_ error: Error) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingCommand = nil
        continuation.resume(throwing: error)
    }

    func send(_ command: String, timeout: TimeInterval) async throws -> String {
        if pendingContinuation != nil {
            throw AppError.commandInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
            pendingCommand = command

            transport.send(command) { [weak self] result in
                guard let self else { return }

                switch result {
                case .success:
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        await self.timeoutIfStillPending(command: command)
                    }
                case .failure(let error):
                    Task {
                        await self.handleError(error)
                    }
                }
            }
        }
    }

    private func timeoutIfStillPending(command: String) {
        guard let continuation = pendingContinuation, pendingCommand == command else { return }
        pendingContinuation = nil
        pendingCommand = nil
        continuation.resume(throwing: AppError.timeout(command))
    }
}
