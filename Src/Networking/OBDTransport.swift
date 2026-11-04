import Foundation
import Network

/// Small socket boundary keeps connection lifecycle tests independent of hardware.
protocol AdapterTCPConnection: AnyObject {
    var stateUpdateHandler: ((NWConnection.State) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func cancel()
    func send(_ data: Data, completion: @escaping (Error?) -> Void)
    func receive(_ completion: @escaping (Data?, Bool, Error?) -> Void)
}

private final class NetworkAdapterConnection: AdapterTCPConnection {
    private let connection: NWConnection
    var stateUpdateHandler: ((NWConnection.State) -> Void)? {
        get { connection.stateUpdateHandler }
        set { connection.stateUpdateHandler = newValue }
    }
    init(host: String, port: UInt16) {
        connection = NWConnection(host: NWEndpoint.Host(host),
                                  port: NWEndpoint.Port(rawValue: port)!,
                                  using: OBDTransport.parameters())
    }
    func start(queue: DispatchQueue) { connection.start(queue: queue) }
    func cancel() { connection.cancel() }
    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        connection.send(content: data, completion: .contentProcessed { completion($0) })
    }
    func receive(_ completion: @escaping (Data?, Bool, Error?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, complete, error in
            completion(data, complete, error)
        }
    }
}

final class OBDTransport: OBDTransporting {
    private var connection: (any AdapterTCPConnection)?
    private let queue = DispatchQueue(label: "obd.transport.queue")
    private let responseBuffer = AdapterResponseBuffer()
    private let host: String
    private let port: UInt16
    private let makeConnection: (String, UInt16) -> any AdapterTCPConnection
    private var generation = UUID()

    var onStateChanged: ((OBDTransportState) -> Void)?
    var onResponse: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    init(host: String, port: UInt16,
         makeConnection: @escaping (String, UInt16) -> any AdapterTCPConnection = {
             NetworkAdapterConnection(host: $0, port: $1)
         }) {
        self.host = host
        self.port = port
        self.makeConnection = makeConnection
    }

    deinit {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
    }

    static func parameters() -> NWParameters {
        let parameters = NWParameters.tcp
        // EconTool explicitly binds its socket to the adapter's local network.
        // Select Wi-Fi on Apple platforms without hardcoding a local subnet.
        parameters.requiredInterfaceType = .wifi
        return parameters
    }

    func connect() {
        queue.async { [self] in
            closeCurrentConnection()
            guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, port > 0 else {
                onStateChanged?(.failed("Invalid adapter address or port"))
                onError?(AppError.transportError("Invalid adapter address or port"))
                return
            }
            onStateChanged?(.setup)
            let socket = makeConnection(host, port)
            connection = socket
            let session = generation
            socket.stateUpdateHandler = { [weak self] state in
                self?.queue.async { [weak self] in
                    guard let self, self.generation == session else { return }
                    self.onStateChanged?(Self.mapState(state))
                    switch state {
                    case .ready: self.receive(socket, session: session)
                    case .failed(let error): self.fail(error)
                    case .cancelled: self.closeCurrentConnection()
                    default: break
                    }
                }
            }
            socket.start(queue: queue)
        }
    }

    func disconnect() {
        queue.async { [self] in
            closeCurrentConnection()
            onStateChanged?(.disconnected)
        }
    }

    func send(_ command: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            guard let connection else { completion(.failure(AppError.notConnected)); return }
            let session = generation
            connection.send(Data((command + "\r").utf8)) { [weak self] error in
                guard let self else { completion(.failure(AppError.notConnected)); return }
                self.queue.async {
                    guard self.generation == session else {
                        completion(.failure(AppError.notConnected))
                        return
                    }
                    if let error {
                        self.fail(error)
                        completion(.failure(error))
                    } else { completion(.success(())) }
                }
            }
        }
    }

    private func receive(_ socket: any AdapterTCPConnection, session: UUID) {
        socket.receive { [weak self] data, isComplete, error in
            self?.queue.async { [weak self] in
                guard let self, self.generation == session else { return }
                if let data, !data.isEmpty {
                    for response in self.responseBuffer.append(data) { self.onResponse?(response) }
                }
                if let error { self.fail(error); return }
                if isComplete {
                    self.fail(AppError.transportError("The Wi-Fi adapter closed the connection."))
                    return
                }
                self.receive(socket, session: session)
            }
        }
    }

    private func fail(_ error: Error) {
        closeCurrentConnection()
        onStateChanged?(.failed(error.localizedDescription))
        onError?(error)
    }

    private func closeCurrentConnection() {
        generation = UUID()
        let previous = connection
        connection = nil
        previous?.stateUpdateHandler = nil
        previous?.cancel()
        responseBuffer.clear()
    }

    private static func mapState(_ state: NWConnection.State) -> OBDTransportState {
        switch state {
        case .setup: return .setup
        case .waiting(let error): return .waiting(error.localizedDescription)
        case .preparing: return .preparing
        case .ready: return .ready("Connected")
        case .failed(let error): return .failed(error.localizedDescription)
        case .cancelled: return .cancelled
        @unknown default: return .unknown("Unknown network state")
        }
    }
}
