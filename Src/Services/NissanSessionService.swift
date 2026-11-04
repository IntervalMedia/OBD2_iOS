import Foundation
import Combine

/// Reuses OBDMVP's selected Wi-Fi/BLE transport, with exclusive session ownership.
private struct NissanQueueTransport: ELMTransport {
    let queue: OBDCommandQueue
    let log: @Sendable (String) async -> Void
    let disconnect: @Sendable () async -> Void

    func exchange(_ command: String) async throws -> String {
        try await exchange(command, timeout: 3)
    }

    func exchange(_ command: String, timeout: TimeInterval) async throws -> String {
        await log("Nissan TX \(command)")
        let response = try await queue.send(command, timeout: timeout)
        await log("Nissan RX \(response)")
        return response
    }

    func close() async { await disconnect() }
}

enum NissanModule: String, CaseIterable, Identifiable {
    case engine = "Engine", cvt = "CVT information"
    var id: String { rawValue }
}

@MainActor
final class NissanSessionService: ObservableObject {
    @Published var module: NissanModule = .engine
    @Published private(set) var workSupport: NissanWorkSupportCapabilities?
    @Published private(set) var cvtInformation: NissanCVTInformation?
    @Published private(set) var running = false
    @Published private(set) var polling = false
    @Published private(set) var busy = false
    @Published private(set) var status = "Connect your adapter first, then start a Nissan session."
    @Published private(set) var identity: ECUIdentity?
    @Published private(set) var codes: [TroubleCode] = []
    @Published private(set) var values: [NissanParameter: Double] = [:]
    @Published private(set) var errors: [NissanParameter: String] = [:]
    @Published private(set) var samples: [NissanLogRecord] = []
    @Published private(set) var supported: Set<UInt16>?
    @Published var profile = NissanECUProfile(rawValue: UserDefaults.standard.string(forKey: "nissan.profile") ?? "") ?? .petrol {
        didSet { UserDefaults.standard.set(profile.rawValue, forKey: "nissan.profile") }
    }
    @Published var selected = Set(NissanParameter.allCases)
    private var client: DiagnosticClient?
    private var cvtClient: NissanCVTClient?
    private var acquisition: Task<Void, Never>?
    private var connectionObserver: AnyCancellable?

    var availableParameters: [NissanParameter] {
        guard module == .engine else { return [] }
        return NissanParameter.allCases.filter { (try? profile.register(for: $0)) != nil }
    }

    func start(using obd: OBDService) async {
        guard !running, !busy else { return }
        busy = true
        defer { busy = false }
        await stopLogging()
        connectionObserver = nil
        await client?.close()
        await cvtClient?.close()
        client = nil
        cvtClient = nil
        cvtInformation = nil
        workSupport = nil
        values = [:]; errors = [:]; samples = []; codes = []; identity = nil; supported = nil
        do {
            let queue = try await obd.beginNissanSession()
            let transport = NissanQueueTransport(queue: queue, log: { message in
                await obd.logNissan(message)
            }, disconnect: { await obd.endNissanSession(queue: queue) })
            status = "Initializing Nissan session…"
            if module == .engine {
                let client = DiagnosticClient(transport: transport, profile: profile)
                self.client = client
                try await client.initialize()
                identity = try await client.identifyECU()
            } else {
                let client = NissanCVTClient(transport: transport)
                cvtClient = client
                try await client.initialize()
                cvtInformation = try await client.readInformation()
            }
            connectionObserver = obd.$isConnected.dropFirst().sink { [weak self] connected in
                if !connected {
                    self?.acquisition?.cancel()
                    self?.running = false
                    self?.polling = false
                    self?.status = "Adapter disconnected. Start a new session to continue."
                }
            }
            running = true
            status = module == .engine
                ? "Engine connected. Choose live data or a diagnostic action."
                : "CVT connected. Your transmission information is ready."
        } catch {
            await client?.close()
            await cvtClient?.close()
            client = nil
            cvtClient = nil
            status = error.localizedDescription
        }
    }

    func stop() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await stopLogging()
        connectionObserver = nil
        await client?.close()
        await cvtClient?.close()
        client = nil
        cvtClient = nil
        running = false
        status = "Session ended. Reconnect and initialize for generic OBD-II."
    }

    func startLogging() {
        guard running, !busy, !polling else { return }
        guard let client else { status = "Start an engine session before logging live data."; return }
        let parameters = availableParameters.filter { selected.contains($0) }
        guard !parameters.isEmpty else { status = "Select at least one parameter."; return }
        polling = true
        acquisition = Task {
            defer { polling = false }
            do {
                let stream = try await NissanDataLogger(client: client).stream(parameters: parameters, cycleDelay: .seconds(1))
                for try await cycle in stream {
                    for sample in cycle {
                        if let value = sample.value { record(sample.parameter, value: value, timestamp: sample.timestamp) }
                        if let error = sample.error {
                            values = values.filter { $0.key != sample.parameter }
                            errors = errors.merging([sample.parameter: error.localizedDescription]) { _, new in new }
                        }
                    }
                }
            } catch is CancellationError { }
            catch { status = "Logging stopped: " + error.localizedDescription }
        }
    }

    func stopLogging() async {
        let pending = acquisition
        acquisition?.cancel()
        await pending?.value
        acquisition = nil
        polling = false
    }

    func discoverWorkSupport() async {
        workSupport = nil
        await perform { client in
            self.workSupport = try await client.discoverWorkSupport()
            self.status = "Read ECU work-support capabilities."
        }
    }

    func performLearning(_ learning: NissanLearning) async {
        await perform { client in
            self.status = "Running \(learning.title)… This can take up to 120 seconds."
            do {
                try await client.performLearning(learning)
                await client.close()
                self.status = "ECU confirmed completion. Turn ignition off for at least 10 seconds before reconnecting."
            } catch {
                await client.close()
                self.status = "Completion not confirmed: " + error.localizedDescription + " No automatic restart was sent. Follow the vehicle service procedure before reconnecting."
            }
            self.running = false
            self.identity = nil
            self.workSupport = nil
        }
    }

    func readCVTInformation() async {
        guard running, !busy, let cvtClient else { return }
        busy = true
        defer { busy = false }
        cvtInformation = nil
        do {
            cvtInformation = try await cvtClient.readInformation()
            status = "CVT information updated."
        } catch { status = error.localizedDescription }
    }

    func readCodes() async { await perform { client in
        self.codes = try await client.readTroubleCodes()
        self.status = "Read \(self.codes.count) Nissan fault codes."
    } }

    func clearCodes() async { await perform { client in
        try await client.clearTroubleCodes()
        self.codes = []
        self.status = "Clear acknowledged. Read codes again to verify."
    } }

    func readSupportedRegisters() async { await perform { client in
        self.supported = try await client.supportedRegisters(base: 0x1100)
        self.status = "Read supported register bitmap for 1101–1120."
    } }

    private func perform(_ operation: (DiagnosticClient) async throws -> Void) async {
        guard running, !busy else { return }
        guard let client else { status = "Start an engine session before running diagnostics."; return }
        busy = true
        defer { busy = false }
        await stopLogging()
        do { try await operation(client) }
        catch { status = error.localizedDescription + " No automatic retry was sent." }
    }

    private func record(_ parameter: NissanParameter, value: Double, timestamp: Date) {
        values = values.merging([parameter: value]) { _, new in new }
        errors = errors.filter { $0.key != parameter }
        samples = Array((samples + [NissanLogRecord(timestamp: timestamp, source: "live", parameter: parameter, value: value)]).suffix(5000))
    }
}
