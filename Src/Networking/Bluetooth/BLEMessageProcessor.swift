import Foundation

final class BLEMessageProcessor {
    private var buffer = Data()
    private let maxBufferSize = 4096
    private var pendingResponse: ((Result<String, Error>) -> Void)?

    func processReceivedData(_ data: Data) {
        buffer.append(data)

        guard let text = String(data: buffer, encoding: .utf8) else {
            if buffer.count > maxBufferSize {
                buffer.removeAll()
            }
            return
        }

        guard text.contains(">") else { return }

        let cleaned = text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: ">", with: "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        buffer.removeAll()

        let completion = pendingResponse
        pendingResponse = nil

        guard let completion else { return }

        if cleaned.uppercased().contains("NO DATA") || cleaned.isEmpty {
            completion(.failure(AppError.invalidResponse))
        } else {
            completion(.success(cleaned))
        }
    }

    func prepareForResponse(completion: @escaping (Result<String, Error>) -> Void) {
        pendingResponse = completion
    }

    func failPendingResponse(_ error: Error) {
        let completion = pendingResponse
        pendingResponse = nil
        completion?(.failure(error))
    }

    func reset() {
        buffer.removeAll()
        failPendingResponse(AppError.notConnected)
    }
}
