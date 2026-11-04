import Foundation

/// Bounded asynchronous cycles. Cancel the consuming Task before a DTC operation;
/// cancellation drains the in-flight reply, then stops between commands. It never clears codes.
public struct NissanDataLogger: Sendable {
    public let client: DiagnosticClient
    public init(client: DiagnosticClient) { self.client = client }

    public func stream(parameters: [NissanParameter], cycleDelay: Duration = .zero) async throws -> AsyncThrowingStream<[DiagnosticSample], Error> {
        guard !parameters.isEmpty else { return AsyncThrowingStream { $0.finish() } }
        try await client.prepareDataLogging()
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let producer = Task {
                do {
                    while !Task.isCancelled {
                        var cycle: [DiagnosticSample] = []
                        for parameter in parameters {
                            try Task.checkCancellation()
                            // An unstructured acquisition is deliberately not cancelled with the
                            // consumer. Drain the current ELM response, then stop between commands.
                            let pendingRead = Task { try await client.readCycle(parameters: [parameter]) }
                            let samples = try await pendingRead.value
                            try Task.checkCancellation()
                            cycle = cycle + samples
                        }
                        if case .terminated = continuation.yield(cycle) { break }
                        try await Task.sleep(for: cycleDelay)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
}
