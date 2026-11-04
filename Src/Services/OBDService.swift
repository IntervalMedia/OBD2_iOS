import Foundation

@MainActor
final class OBDService: ObservableObject {
    @Published private(set) var connectionPhase: ConnectionPhase = .disconnected
    @Published private(set) var isPolling = false
    @Published private(set) var isReadingDTCs = false
    @Published private(set) var isClearingDTCs = false
    @Published private(set) var hasReadDTCs = false
    @Published private(set) var diagnosticError: String?
    @Published private(set) var isConnected = false
    @Published private(set) var isInitialized = false
    @Published private(set) var isNissanSessionActive = false
    @Published private(set) var latestSample: LiveSample?
    @Published private(set) var liveSamples: [LiveSample]
    @Published private(set) var dtcs: [DiagnosticTroubleCode] = []
    @Published private(set) var vehicleInfo: VehicleInfo
    @Published private(set) var connectionStateDescription: String = "Disconnected"
    @Published private(set) var bluetoothAdapters: [BluetoothAdapterDescriptor] = []
    @Published private(set) var isScanningBluetoothAdapters = false
    @Published private(set) var selectedBluetoothAdapter: BluetoothAdapterDescriptor?
    @Published var settings: ConnectionSettings {
        didSet {
            persistenceStore.saveConnectionSettings(settings)
            syncSelectedBluetoothAdapterFromSettings()
        }
    }

    private var transport: OBDTransporting
    private var commandQueue: OBDCommandQueue
    private let logStore: LogStore
    private let persistenceStore: PersistenceStore
    private var pollingTask: Task<Void, Never>?
    private var transportGeneration = UUID()
    private var setupTask: Task<Void, Never>?
    private var connectionDeadline: Task<Void, Never>?
    private var initializeWhenConnected = false

    var isConnecting: Bool { connectionPhase == .connecting }
    var isInitializing: Bool {
        if case .initializing = connectionPhase { return true }
        return false
    }
    var connectionError: String? {
        if case .failed(let message) = connectionPhase { return message }
        return nil
    }

    init(logStore: LogStore, persistenceStore: PersistenceStore) {
        let settings = persistenceStore.loadConnectionSettings()
        let liveSamples = persistenceStore.loadLiveSamples()
        let vehicleInfo = persistenceStore.loadVehicleInfo()
        let transport = OBDService.makeTransport(for: settings)

        self.logStore = logStore
        self.persistenceStore = persistenceStore
        self.settings = settings
        self.liveSamples = liveSamples
        self.vehicleInfo = vehicleInfo
        self.latestSample = liveSamples.last
        self.transport = transport
        self.commandQueue = OBDCommandQueue(transport: transport)

        configureTransportCallbacks()
        syncSelectedBluetoothAdapterFromSettings()
    }

    func connect() { beginConnection(initialize: false) }

    func connectAndInitialize() {
        guard !isConnecting, !isInitializing, !isNissanSessionActive else { return }
        if isConnected {
            guard !isInitialized else { return }
            setupTask = Task { await initializeAdapter() }
        } else {
            beginConnection(initialize: true)
        }
    }

    private func beginConnection(initialize: Bool) {
        guard !isNissanSessionActive, !isConnecting, !isInitializing else { return }
        if settings.transportType == .wifi {
            guard !settings.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, settings.port > 0 else {
                connectionPhase = .failed("Enter your adapter's host address and a port between 1 and 65535.")
                return
            }
        } else if selectedBluetoothAdapter == nil {
            connectionPhase = .failed("Scan for Bluetooth adapters and select yours before connecting.")
            return
        }
        rebuildTransportIfNeeded()
        initializeWhenConnected = initialize
        connectionPhase = .connecting
        connectionStateDescription = "Connecting to adapter…"
        logStore.append("Connecting via \(settings.transportType.displayName)")
        let generation = transportGeneration
        connectionDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, self.transportGeneration == generation, !self.isConnected else { return }
            self.failSetup("Adapter not found. Check its power and your Wi-Fi network or Bluetooth selection, then try again.")
        }
        transport.connect()
    }

    func disconnect() {
        stopPolling()
        setupTask?.cancel()
        setupTask = nil
        connectionDeadline?.cancel()
        connectionDeadline = nil
        initializeWhenConnected = false
        // Invalidate callbacks and suspended work before closing the old transport.
        transportGeneration = UUID()
        transport.disconnect()
        let queue = commandQueue
        Task { await queue.cancelPending() }
        isNissanSessionActive = false
        isConnected = false
        isInitialized = false
        isReadingDTCs = false
        isClearingDTCs = false
        isScanningBluetoothAdapters = false
        hasReadDTCs = false
        dtcs = []
        connectionPhase = .disconnected
        connectionStateDescription = "Disconnected"
        logStore.append("Disconnected")
    }

    private func failSetup(_ message: String) {
        disconnect()
        connectionPhase = .failed(message)
        connectionStateDescription = message
        logStore.append(message)
    }

    func scanForBluetoothAdapters() async {
        guard !isNissanSessionActive else { return }
        settings.transportType = .bluetoothLE
        rebuildTransportIfNeeded()

        guard let bluetoothTransport = transport as? BluetoothELM327Transport else { return }
        await bluetoothTransport.scanForAdapters()
    }

    func selectBluetoothAdapter(_ adapter: BluetoothAdapterDescriptor) {
        guard !isNissanSessionActive else { return }
        selectedBluetoothAdapter = adapter
        settings.preferredBluetoothPeripheralID = adapter.identifier
        settings.preferredBluetoothPeripheralName = adapter.displayName

        if let bluetoothTransport = transport as? BluetoothELM327Transport {
            bluetoothTransport.selectAdapter(adapter)
        }
    }

    func initializeAdapter() async {
        guard isConnected, !isNissanSessionActive, !isInitializing else { return }
        let generation = transportGeneration
        let queue = commandQueue
        isInitialized = false
        connectionPhase = .initializing(step: 0, total: OBDCommandBuilder.initSequence.count + 1)
        stopPolling()
        do {
            try await queue.waitUntilIdle(timeout: settings.commandTimeoutSeconds + 1)
            let commands = OBDCommandBuilder.initSequence + [OBDCommandBuilder.supportedPIDs]
            for (index, command) in commands.enumerated() {
                try Task.checkCancellation()
                guard transportGeneration == generation, !isNissanSessionActive, isConnected else { throw CancellationError() }
                connectionPhase = .initializing(step: index + 1, total: commands.count)
                let response = try await send(command, timeout: command == "0100" ? 10 : 4)
                guard transportGeneration == generation, !isNissanSessionActive, isConnected else { throw CancellationError() }
                try AdapterSetupResponse.validate(response, command: command)
                logStore.append("Init \(command) acknowledged")
            }
            try Task.checkCancellation()
            isInitialized = true
            connectionPhase = .ready
            connectionStateDescription = "Vehicle ready"
        } catch {
            guard transportGeneration == generation else { return }
            failSetup("Could not initialize the vehicle. Check that the ignition is on and the adapter is firmly connected. \(error.localizedDescription)")
        }
    }

    func readVIN() async {
        guard isConnected, isInitialized, !isNissanSessionActive else { return }
        let generation = transportGeneration
        do {
            let response = try await send(OBDCommandBuilder.vin, timeout: 5.0)
            guard generation == transportGeneration, !isNissanSessionActive else { return }
            vehicleInfo.vin = OBDParser.parseVIN(response)
            persistenceStore.saveVehicleInfo(vehicleInfo)
            logStore.append("VIN -> \(vehicleInfo.vin ?? "Unavailable")")
        } catch {
            logStore.append("VIN read failed: \(error.localizedDescription)")
        }
    }

    func readDTCs() async {
        guard isConnected, isInitialized, !isNissanSessionActive, !isReadingDTCs, !isClearingDTCs else { return }
        let generation = transportGeneration
        let queue = commandQueue
        isReadingDTCs = true
        hasReadDTCs = false
        diagnosticError = nil
        stopPolling()
        defer { if generation == transportGeneration { isReadingDTCs = false } }
        do {
            try await queue.waitUntilIdle(timeout: settings.commandTimeoutSeconds + 1)
            guard generation == transportGeneration, isConnected, !isNissanSessionActive else { return }
            let response = try await send(OBDCommandBuilder.storedDTCs, timeout: 5.0)
            guard generation == transportGeneration, !isNissanSessionActive else { return }
            guard AdapterSetupResponse.isDiagnosticResponse(response, service: "43") else { throw AppError.invalidResponse }
            let codes = AdapterSetupResponse.lines(response, command: "03").flatMap { OBDParser.parseStoredDTCs($0) }
            dtcs = Array(Set(codes.map(\.code))).sorted().map { DiagnosticTroubleCode(code: $0) }
            hasReadDTCs = true
            logStore.append("DTC count -> \(dtcs.count)")
        } catch {
            guard generation == transportGeneration else { return }
            diagnosticError = "Could not read fault codes. \(error.localizedDescription) Try again after checking the connection."
            logStore.append(diagnosticError!)
        }
    }

    func clearDTCs() async {
        guard isConnected, isInitialized, !isNissanSessionActive, !isReadingDTCs, !isClearingDTCs else { return }
        let generation = transportGeneration
        let queue = commandQueue
        isClearingDTCs = true
        diagnosticError = nil
        stopPolling()
        defer { if generation == transportGeneration { isClearingDTCs = false } }
        do {
            try await queue.waitUntilIdle(timeout: settings.commandTimeoutSeconds + 1)
            guard generation == transportGeneration, isConnected, !isNissanSessionActive else { return }
            let response = try await send(OBDCommandBuilder.clearDTCs, timeout: 5.0)
            guard generation == transportGeneration, !isNissanSessionActive else { return }
            guard AdapterSetupResponse.isDiagnosticResponse(response, service: "44") else { throw AppError.invalidResponse }
            dtcs = []
            hasReadDTCs = false
            logStore.append("Clear acknowledged. Read codes again to verify.")
        } catch {
            guard generation == transportGeneration else { return }
            diagnosticError = "Clear was not confirmed. \(error.localizedDescription) No automatic retry was sent."
            logStore.append(diagnosticError!)
        }
    }

    func startPolling() {
        guard isConnected, isInitialized, !isNissanSessionActive, !isReadingDTCs, !isClearingDTCs else { return }
        stopPolling()
        isPolling = true
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(self.settings.pollingIntervalSeconds * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        isPolling = false
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
        guard isConnected, isInitialized, !isNissanSessionActive else { return }

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

    // A Nissan session changes adapter headers and protocol. Reserve the shared queue,
    // drain any generic request, and require generic initialization again afterwards.
    func beginNissanSession() async throws -> OBDCommandQueue {
        guard isConnected else { throw AppError.notConnected }
        guard !isNissanSessionActive, !isInitializing, !isReadingDTCs, !isClearingDTCs else { throw AppError.commandInProgress }
        isNissanSessionActive = true
        isInitialized = false
        let reservedQueue = commandQueue
        let previousPolling = pollingTask
        stopPolling()
        await previousPolling?.value
        do {
            try await reservedQueue.waitUntilIdle(timeout: settings.commandTimeoutSeconds + 1)
            guard commandQueue === reservedQueue, isConnected, isNissanSessionActive else { throw AppError.notConnected }
            return reservedQueue
        } catch {
            endNissanSession(queue: reservedQueue)
            throw error
        }
    }

    func endNissanSession(queue: OBDCommandQueue) {
        // A failed old session must never close a replacement connection.
        guard commandQueue === queue, isNissanSessionActive else { return }
        disconnect()
    }

    func logNissan(_ message: String) { logStore.append(message) }

    private func send(_ command: String, timeout: TimeInterval? = nil) async throws -> String {
        guard !isNissanSessionActive else { throw CancellationError() }
        try Task.checkCancellation()
        let generation = transportGeneration
        logStore.append("TX \(command)")
        let response = try await commandQueue.send(command, timeout: timeout ?? settings.commandTimeoutSeconds)
        guard generation == transportGeneration, !isNissanSessionActive else { throw CancellationError() }
        try Task.checkCancellation()
        logStore.append("RX \(response)")
        return response
    }

    private func configureTransportCallbacks() {
        let generation = transportGeneration
        let queue = commandQueue
        transport.onStateChanged = { [weak self] state in
            Task { @MainActor in
                guard self?.transportGeneration == generation else { return }
                self?.handleTransportState(state)
            }
        }

        transport.onResponse = { [weak queue] response in
            Task {
                await queue?.handleResponse(response)
            }
        }

        transport.onError = { [weak self, weak queue] error in
            Task {
                await queue?.handleError(error)
                await MainActor.run {
                    guard self?.transportGeneration == generation else { return }
                    self?.logStore.append("Transport error: \(error.localizedDescription)")
                }
            }
        }

        if let bluetoothTransport = transport as? BluetoothELM327Transport {
            bluetoothTransport.onAdaptersChanged = { [weak self] adapters in
                guard self?.transportGeneration == generation else { return }
                self?.bluetoothAdapters = adapters
                self?.syncSelectedBluetoothAdapterFromSettings()
            }
            bluetoothTransport.onScanningChanged = { [weak self] isScanning in
                guard self?.transportGeneration == generation else { return }
                self?.isScanningBluetoothAdapters = isScanning
            }
        } else {
            bluetoothAdapters = []
            isScanningBluetoothAdapters = false
            selectedBluetoothAdapter = nil
        }
    }

    private func rebuildTransportIfNeeded() {
        connectionPhase = .disconnected
        setupTask?.cancel()
        setupTask = nil
        connectionDeadline?.cancel()
        connectionDeadline = nil
        initializeWhenConnected = false
        hasReadDTCs = false
        dtcs = []
        diagnosticError = nil
        isReadingDTCs = false
        isClearingDTCs = false
        stopPolling()
        isConnected = false
        isInitialized = false
        transportGeneration = UUID()
        let previousQueue = commandQueue
        Task { await previousQueue.cancelPending() }
        transport.disconnect()
        transport = OBDService.makeTransport(for: settings)
        commandQueue = OBDCommandQueue(transport: transport)
        configureTransportCallbacks()
        syncSelectedBluetoothAdapterFromSettings()
    }

    private func handleTransportState(_ state: OBDTransportState) {
        // BLE discovery completes without opening a vehicle connection.
        if case .disconnected = state, connectionPhase == .disconnected, !isConnected {
            connectionStateDescription = state.description
            return
        }
        connectionStateDescription = state.description
        isConnected = state.isConnected
        switch state {
        case .ready:
            connectionDeadline?.cancel()
            connectionDeadline = nil
            if initializeWhenConnected {
                initializeWhenConnected = false
                setupTask = Task { await initializeAdapter() }
            } else if !isInitialized && !isInitializing && !isNissanSessionActive {
                connectionPhase = .adapterConnected
            }
        case .failed, .cancelled, .disconnected, .unauthorized, .unsupported:
            failSetup(state.description + " Check the adapter connection and access permissions, then try again.")
        default:
            break
        }
    }

    private func syncSelectedBluetoothAdapterFromSettings() {
        guard settings.transportType == .bluetoothLE else {
            selectedBluetoothAdapter = nil
            return
        }

        if let preferredID = settings.preferredBluetoothPeripheralID,
           let matching = bluetoothAdapters.first(where: { $0.identifier == preferredID }) {
            selectedBluetoothAdapter = matching
            return
        }

        if let preferredID = settings.preferredBluetoothPeripheralID {
            selectedBluetoothAdapter = BluetoothAdapterDescriptor(
                identifier: preferredID,
                name: settings.preferredBluetoothPeripheralName ?? "Saved Adapter",
                signalStrength: nil
            )
            return
        }

        selectedBluetoothAdapter = nil
    }

    private static func makeTransport(for settings: ConnectionSettings) -> OBDTransporting {
        switch settings.transportType {
        case .wifi:
            return OBDTransport(host: settings.host, port: settings.port)
        case .bluetoothLE:
            let descriptor: BluetoothAdapterDescriptor?
            if let identifier = settings.preferredBluetoothPeripheralID {
                descriptor = BluetoothAdapterDescriptor(
                    identifier: identifier,
                    name: settings.preferredBluetoothPeripheralName ?? "Saved Adapter",
                    signalStrength: nil
                )
            } else {
                descriptor = nil
            }
            return BluetoothELM327Transport(selectedAdapter: descriptor)
        }
    }
}
