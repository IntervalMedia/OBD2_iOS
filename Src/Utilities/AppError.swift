import Foundation

enum AppError: LocalizedError {
    case notConnected
    case invalidResponse
    case commandInProgress
    case timeout(String)
    case transportError(String)
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to the OBD adapter."
        case .invalidResponse:
            return "The adapter returned an invalid response."
        case .commandInProgress:
            return "Another command is already in progress."
        case .timeout(let command):
            return "Timed out waiting for response to \(command)."
        case .transportError(let message):
            return "Transport error: \(message)"
        case .exportFailed:
            return "Failed to export CSV."
        }
    }
}
