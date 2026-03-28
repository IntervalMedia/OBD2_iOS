import Foundation
import Network

final class OBDTransport {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "obd.transport.queue")
    private let responseBuffer = AdapterResponseBuffer()

    var onStateChanged: ((NWConnection.State) -> Void)?
    var onResponse: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    func connect(host: String, port: UInt16) {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            self?.onStateChanged?(state)
            if case .ready = state {
                self?.startReceiveLoop()
            }
        }

        connection.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        responseBuffer.clear()
    }

    func send(_ command: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let connection else {
            completion(.failure(AppError.notConnected))
            return
        }

        let payload = Data((command + "\r").utf8)
        connection.send(content: payload, completion: .contentProcessed { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        })
    }

    private func startReceiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.onError?(error)
            }

            if let data, !data.isEmpty {
                let responses = self.responseBuffer.append(data)
                for response in responses {
                    self.onResponse?(response)
                }
            }

            if !isComplete {
                self.startReceiveLoop()
            }
        }
    }
}
