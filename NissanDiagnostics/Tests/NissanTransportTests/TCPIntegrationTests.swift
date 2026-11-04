import XCTest
import Network
import NissanCore
@testable import NissanTransport

final class TCPIntegrationTests: XCTestCase {
    func testRealTCPFramingAndCompleteDTCFlow() async throws {
        let server = try LoopbackELM()
        let port = try await server.start()
        defer { server.stop() }
        let transport = TCPTransport(host: "127.0.0.1", port: port)
        let client = DiagnosticClient(transport: transport)
        try await client.initialize()
        _ = try await client.identifyECU()
        let codes = try await client.readTroubleCodes()
        XCTAssertEqual(codes.first?.code, "P0123")
        try await client.clearTroubleCodes()
        try await client.prepareDataLogging()
        let samples = try await client.readCycle(parameters: [.battery])
        XCTAssertEqual(samples.first?.value ?? 0, 12.8, accuracy: 0.001)
        await client.close()
        let commands = server.commands
        XCTAssertTrue(commands.contains("17FF00"))
        XCTAssertEqual(commands.filter { $0 == "14FF00" }.count, 1)
    }
    func testShortTimeoutAndInvalidCommand() async throws {
        let server = try LoopbackELM(silent: true)
        let port = try await server.start()
        defer { server.stop() }
        let transport = TCPTransport(host: "127.0.0.1", port: port)
        do { _ = try await transport.exchange("ATZ\r14FF00", timeout: 1); XCTFail() }
        catch { XCTAssertTrue(error is TCPTransport.TransportError) }
        do { _ = try await transport.exchange("ATZ", timeout: 0.1); XCTFail() }
        catch { XCTAssertTrue(error is TCPTransport.TransportError) }
        await transport.close()
        XCTAssertEqual(server.commands, ["ATZ"])
    }
}

/// Tests bind only to loopback. No vehicle or external adapter is contacted.
private final class LoopbackELM: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "NissanTests.loopback")
    private let lock = NSLock()
    private var recorded: [String] = []
    private var connections: [NWConnection] = []
    private let silent: Bool
    var commands: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    init(silent: Bool = false) throws {
        self.silent = silent
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready: listener.stateUpdateHandler = nil; continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error): listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                connections.append(connection)
                connection.start(queue: queue)
                receive(connection, buffer: Data())
            }
            listener.start(queue: queue)
        }
    }
    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [self] data, _, ended, error in
            if ended || error != nil { return }
            var bytes = buffer + (data ?? Data())
            while let boundary = bytes.firstIndex(of: 13) {
                let command = String(decoding: bytes[..<boundary], as: UTF8.self)
                bytes = Data(bytes[bytes.index(after: boundary)...])
                lock.lock(); recorded = recorded + [command]; lock.unlock()
                if !silent {
                    let payload: String
                    switch command {
                    case "ATZ": payload = "ELM327 v1.5\r>"
                    case "1081": payload = "5081\r>"
                    case "10C0": payload = "50C0\r>"
                    case "2183": payload = "6183414243444501\r>"
                    case "17FF00": payload = "5701012301\r>"
                    case "14FF00": payload = "54\r>"
                    case "221103": payload = "621103A0\r>"
                    default: payload = "OK\r>"
                    }
                    // Split responses to exercise incremental prompt assembly.
                    let split = payload.index(payload.startIndex, offsetBy: payload.count / 2)
                    connection.send(content: Data(payload[..<split].utf8), completion: .contentProcessed { _ in
                        connection.send(content: Data(payload[split...].utf8), completion: .contentProcessed { _ in })
                    })
                }
            }
            receive(connection, buffer: bytes)
        }
    }
    func stop() { queue.async { self.listener.cancel(); self.connections.forEach { $0.cancel() }; self.connections = [] } }
}
