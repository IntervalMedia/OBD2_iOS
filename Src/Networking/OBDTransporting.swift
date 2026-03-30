import Foundation

enum OBDTransportState: Equatable {
    case disconnected
    case setup
    case preparing
    case scanning
    case connecting(String)
    case ready(String)
    case waiting(String)
    case failed(String)
    case cancelled
    case unauthorized(String)
    case unsupported(String)
    case unknown(String)

    var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .setup:
            return "Setup"
        case .preparing:
            return "Preparing"
        case .scanning:
            return "Scanning"
        case .connecting(let detail):
            return detail.isEmpty ? "Connecting" : "Connecting: \(detail)"
        case .ready(let detail):
            return detail.isEmpty ? "Connected" : detail
        case .waiting(let detail):
            return detail.isEmpty ? "Waiting" : "Waiting: \(detail)"
        case .failed(let detail):
            return detail.isEmpty ? "Failed" : "Failed: \(detail)"
        case .cancelled:
            return "Cancelled"
        case .unauthorized(let detail):
            return detail.isEmpty ? "Bluetooth permission required" : detail
        case .unsupported(let detail):
            return detail.isEmpty ? "Unsupported" : detail
        case .unknown(let detail):
            return detail.isEmpty ? "Unknown" : detail
        }
    }

    var isConnected: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

protocol OBDTransporting: AnyObject {
    var onStateChanged: ((OBDTransportState) -> Void)? { get set }
    var onResponse: ((String) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    func connect()
    func disconnect()
    func send(_ command: String, completion: @escaping (Result<Void, Error>) -> Void)
}
