import Foundation
import Network

@MainActor
final class OBDService: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isInitialized = false
    @Published private(set) var latestSample: LiveSample?
    @Published private(set) var liveSamples: [LiveSample]
    @Published private(set) var dtcs: [DiagnosticTroubleCode] = []
    @Published private(set) var vehicleInfo: VehicleInfo
    @Published private(set) var connectionStateDescription: String = "Disconnected"
    @Published var settings: ConnectionSettings {
        didSet {
            persistenceStore.saveConnectionSettings(settings)
        }
    }

    private let transport = OBDTransport()
    private let logStore: LogStore
    private let persistenceStore: PersistenceStore
    private lazy var commandQueue = OBDCommandQueue(transport: transport)
    private var pollingTask: Task<Void, Never>?

    init(logStore: LogStore, persistenceStore: PersistenceStore) {
        self.logStore = logStore
        self.persistenceStore = persistenceStore
        self.settings = persistenceStore.loadConnectionSettings()
        self.liveSamples = persistenceStore.loadLiveSamples()
        self.vehicleInfo = persistenceStore.loadVehicleInfo()
        self.latestSample = self.liveSamples.last

        transport.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.handleTransportState(state)
            }
        }

        transport.onResponse = { [weak self] response in
            Task {
                await self?.commandQueue.handleResponse(response)
            }
        }

        transport.onError = { [weak self] error in
            Task {
                await self?.commandQueue.handleError(error)
                await MainActor.run {
                    self?.logStore.append("Transport error: \(error.localizedDescription)")
                }
            }
        }
    }

    func connect() {
        logStore.append("Connecting to \(settings.host):\(settings.port)")
        transport.connect(host: settings.host, port: settings.port)
    }

    func disconnect() {
        stopPolling()
        transport.disconnect()
        isConnected = false
        isInitialized = false
        connectionStateDescription = "Disconnected"
        logStore.append("Disconnected")
    }

    func initializeAdapter() async {
        do {
            for command in OBDCommandBuilder.initSequence {
                let response = try await send(command, timeout: 4.0)
                logStore.append("Init \(command) -> \(response)")
            }

            let supported = try await send(OBDCommandBuilder.supportedPIDs, timeout: 4.0)
            logStore.append("Supported PIDs -> \(supported)")
            isInitialized = true
        } catch {
            isInitialized = false
            logStore.append("Initialization failed: \(error.localizedDescription)")
        }
    }

    func readVIN() async {
        do {
            let response = try await send(OBDCommandBuilder.vin, timeout: 5.0)
            vehicleInfo.vin = OBDParser.parseVIN(response)
            persistenceStore.saveVehicleInfo(vehicleInfo)
            logStore.append("VIN -> \(vehicleInfo.vin ?? "Unavailable")")
        } catch {
            logStore.append("VIN read failed: \(error.localizedDescription)")
        }
    }

    func readDTCs() async {
        do {
            let response = try await send(OBDCommandBuilder.storedDTCs, timeout: 5.0)
            dtcs = OBDParser.parseStoredDTCs(response)
            logStore.append("DTC count -> \(dtcs.count)")
        } catch {
            logStore.append("Read DTCs failed: \(error.localizedDescription)")
        }
    }

    func clearDTCs() async {
        do {
            let response = try await send(OBDCommandBuilder.clearDTCs, timeout: 5.0)
            dtcs = []
            logStore.append("Clear DTCs -> \(response)")
        } catch {
            logStore.append("Clear DTCs failed: \(error.localizedDescription)")
        }
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(self.settings.pollingIntervalSeconds * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func clearSamples() {
        liveSamples.removeAll()
        latestSample = nil
        persistenceStore.saveLiveSamples(liveSamples)
        logStore.append("Cleared stored live samples")
    }

    func exportCSV() throws -> URL {
        try CSVExporter.writeCSVToTemporaryFile(samples: liveSamples)
    }

    private func pollOnce() async {
        guard isConnected, isInitialized else { return }

        do {
            let rpmResponse = try await send(OBDCommandBuilder.rpm)
            let speedResponse = try await send(OBDCommandBuilder.speed)
            let coolantResponse = try await send(OBDCommandBuilder.coolantTemp)
            let throttleResponse = try await send(OBDCommandBuilder.throttlePosition)
            let voltageResponse = try await send(OBDCommandBuilder.batteryVoltage)

            let sample = LiveSample(
                timestamp: Date(),
                rpm: OBDParser.parseRPM(rpmResponse),
                speedKph: OBDParser.parseSpeed(speedResponse),
                coolantTempC: OBDParser.parseCoolantTemp(coolantResponse),
                throttlePositionPercent: OBDParser.parseThrottlePosition(throttleResponse),
                batteryVoltage: OBDParser.parseBatteryVoltage(voltageResponse)
            )

            latestSample = sample
            liveSamples.append(sample)

            if liveSamples.count > settings.maxStoredSamples {
                liveSamples.removeFirst(liveSamples.count - settings.maxStoredSamples)
            }

            persistenceStore.saveLiveSamples(liveSamples)
        } catch {
            logStore.append("Poll failed: \(error.localizedDescription)")
        }
    }

    private func send(_ command: String, timeout: TimeInterval? = nil) async throws -> String {
        logStore.append("TX \(command)")
        let response = try await commandQueue.send(command, timeout: timeout ?? settings.commandTimeoutSeconds)
        logStore.append("RX \(response)")
        return response
    }

    private func handleTransportState(_ state: NWConnection.State) {
        switch state {
        case .setup:
            connectionStateDescription = "Setup"
        case .waiting(let error):
            connectionStateDescription = "Waiting: \(error.localizedDescription)"
            isConnected = false
        case .preparing:
            connectionStateDescription = "Preparing"
        case .ready:
            connectionStateDescription = "Connected"
            isConnected = true
        case .failed(let error):
            connectionStateDescription = "Failed: \(error.localizedDescription)"
            isConnected = false
            isInitialized = false
        case .cancelled:
            connectionStateDescription = "Cancelled"
            isConnected = false
            isInitialized = false
        @unknown default:
            connectionStateDescription = "Unknown"
            isConnected = false
        }
    }
}
