import Foundation

enum AppError: LocalizedError {
    case notConnected
    case invalidResponse
    case commandInProgress
    case timeout(String)
    case transportError(String)
    case unsupportedTransport(String)
    case bluetoothUnavailable
    case bluetoothPermissionDenied
    case bluetoothScanFailed(String)
    case bluetoothAdapterNotSelected
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
        case .unsupportedTransport(let message):
            return "Unsupported transport: \(message)"
        case .bluetoothUnavailable:
            return "Bluetooth LE is not available on this device."
        case .bluetoothPermissionDenied:
            return "Bluetooth permission is required to use BLE adapters."
        case .bluetoothScanFailed(let message):
            return "Bluetooth scan failed: \(message)"
        case .bluetoothAdapterNotSelected:
            return "No Bluetooth adapter has been selected."
        case .exportFailed:
            return "Failed to export CSV."
        }
    }
}
