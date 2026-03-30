import CoreBluetooth
import Foundation

// Adapted from SwiftOBD2 BLE transport concepts:
// https://github.com/kkonteh97/SwiftOBD2 at fe6def4e8599671dfc1b9597dbcdbc6a7c078b96 (MIT).
final class BluetoothELM327Transport: NSObject, OBDTransporting {
    private enum Constants {
        static let scanDuration: TimeInterval = 8.0
        static let connectionTimeout: TimeInterval = 10.0
        static let responseTimeout: TimeInterval = 3.0
        static let supportedServices = [
            CBUUID(string: "FFE0"),
            CBUUID(string: "FFF0"),
            CBUUID(string: "18F0")
        ]
        static let readCharacteristicUUIDs = [
            CBUUID(string: "FFE1"),
            CBUUID(string: "FFF1"),
            CBUUID(string: "2AF0")
        ]
        static let writeCharacteristicUUIDs = [
            CBUUID(string: "FFE1"),
            CBUUID(string: "FFF2"),
            CBUUID(string: "2AF1")
        ]
    }

    var onStateChanged: ((OBDTransportState) -> Void)?
    var onResponse: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onAdaptersChanged: (([BluetoothAdapterDescriptor]) -> Void)?
    var onScanningChanged: ((Bool) -> Void)?

    private(set) var selectedAdapter: BluetoothAdapterDescriptor?

    private lazy var centralManager = CBCentralManager(delegate: self, queue: queue)
    private let queue = DispatchQueue(label: "obd.transport.bluetooth.queue", qos: .userInitiated)
    private let messageProcessor = BLEMessageProcessor()
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var discoveredAdapters: [BluetoothAdapterDescriptor] = []
    private var connectedPeripheral: CBPeripheral?
    private var readCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var isScanning = false
    private var scanStopTask: DispatchWorkItem?
    private var connectTimeoutTask: DispatchWorkItem?

    init(selectedAdapter: BluetoothAdapterDescriptor?) {
        self.selectedAdapter = selectedAdapter
        super.init()
        _ = centralManager
    }

    func connect() {
        switch centralManager.state {
        case .poweredOn:
            connectWhenPoweredOn()
        case .poweredOff:
            emitState(.waiting("Bluetooth is powered off"))
        case .unauthorized:
            emitState(.unauthorized(AppError.bluetoothPermissionDenied.localizedDescription))
        case .unsupported:
            emitState(.unsupported(AppError.bluetoothUnavailable.localizedDescription))
        case .resetting:
            emitState(.waiting("Bluetooth is resetting"))
        case .unknown:
            emitState(.setup)
        @unknown default:
            emitState(.unknown("Unexpected Bluetooth state"))
        }
    }

    func disconnect() {
        scanStopTask?.cancel()
        connectTimeoutTask?.cancel()
        if let connectedPeripheral {
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        }
        connectedPeripheral = nil
        readCharacteristic = nil
        writeCharacteristic = nil
        stopScanning()
        messageProcessor.reset()
        emitState(.disconnected)
    }

    func send(_ command: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let connectedPeripheral, let writeCharacteristic else {
            completion(.failure(AppError.notConnected))
            return
        }

        guard let payload = "\(command)\r".data(using: .ascii) else {
            completion(.failure(AppError.invalidResponse))
            return
        }

        messageProcessor.prepareForResponse { [weak self] result in
            switch result {
            case .success(let response):
                self?.onResponse?(response)
            case .failure(let error):
                self?.onError?(error)
            }
        }

        connectedPeripheral.writeValue(payload, for: writeCharacteristic, type: .withResponse)
        queue.asyncAfter(deadline: .now() + Constants.responseTimeout) { [weak self] in
            self?.messageProcessor.failPendingResponse(AppError.timeout(command))
        }
        completion(.success(()))
    }

    func scanForAdapters() async {
        switch centralManager.state {
        case .poweredOn:
            queue.async { [weak self] in
                self?.beginScan()
            }
        case .poweredOff:
            emitScanningChanged(false)
            emitState(.waiting("Bluetooth is powered off"))
        case .unauthorized:
            emitScanningChanged(false)
            emitState(.unauthorized(AppError.bluetoothPermissionDenied.localizedDescription))
        case .unsupported:
            emitScanningChanged(false)
            emitState(.unsupported(AppError.bluetoothUnavailable.localizedDescription))
        case .resetting:
            emitScanningChanged(false)
            emitState(.waiting("Bluetooth is resetting"))
        case .unknown:
            emitScanningChanged(false)
            emitState(.setup)
        @unknown default:
            emitScanningChanged(false)
            emitState(.unknown("Unexpected Bluetooth state"))
        }
    }

    func selectAdapter(_ adapter: BluetoothAdapterDescriptor) {
        selectedAdapter = adapter
    }

    private func connectWhenPoweredOn() {
        if let selectedID = selectedAdapter?.identifier,
           let peripheral = discoveredPeripherals[selectedID] {
            connect(to: peripheral, descriptor: selectedAdapter)
            return
        }

        if let first = discoveredAdapters.first,
           let peripheral = discoveredPeripherals[first.identifier] {
            selectedAdapter = first
            connect(to: peripheral, descriptor: first)
            return
        }

        beginScan(autoConnect: true)
    }

    private func beginScan(autoConnect: Bool = false) {
        guard centralManager.state == .poweredOn else { return }

        discoveredPeripherals.removeAll()
        discoveredAdapters.removeAll()
        emitAdaptersChanged()
        emitState(.scanning)
        isScanning = true
        emitScanningChanged(true)
        centralManager.scanForPeripherals(withServices: Constants.supportedServices, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        let stopTask = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stopScanning()
            if autoConnect {
                if let selectedID = self.selectedAdapter?.identifier,
                   let peripheral = self.discoveredPeripherals[selectedID] {
                    self.connect(to: peripheral, descriptor: self.selectedAdapter)
                } else if let first = self.discoveredAdapters.first,
                          let peripheral = self.discoveredPeripherals[first.identifier] {
                    self.selectedAdapter = first
                    self.connect(to: peripheral, descriptor: first)
                } else {
                    self.emitState(.failed("No compatible BLE adapter found"))
                    self.onError?(AppError.bluetoothScanFailed("No compatible BLE adapter found"))
                }
            } else {
                self.emitState(.disconnected)
            }
        }

        scanStopTask = stopTask
        queue.asyncAfter(deadline: .now() + Constants.scanDuration, execute: stopTask)
    }

    private func stopScanning() {
        scanStopTask?.cancel()
        scanStopTask = nil
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        isScanning = false
        emitScanningChanged(false)
    }

    private func connect(to peripheral: CBPeripheral, descriptor: BluetoothAdapterDescriptor?) {
        stopScanning()
        connectedPeripheral = peripheral
        selectedAdapter = descriptor
        emitState(.connecting(descriptor?.displayName ?? peripheral.name ?? "Adapter"))
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)

        let timeoutTask = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self, let peripheral else { return }
            self.centralManager.cancelPeripheralConnection(peripheral)
            self.emitState(.failed("Bluetooth connection timed out"))
            self.onError?(AppError.transportError("Bluetooth connection timed out"))
        }
        connectTimeoutTask = timeoutTask
        queue.asyncAfter(deadline: .now() + Constants.connectionTimeout, execute: timeoutTask)
    }

    private func emitState(_ state: OBDTransportState) {
        DispatchQueue.main.async {
            self.onStateChanged?(state)
        }
    }

    private func emitScanningChanged(_ isScanning: Bool) {
        DispatchQueue.main.async {
            self.onScanningChanged?(isScanning)
        }
    }

    private func emitAdaptersChanged() {
        let adapters = discoveredAdapters.sorted { lhs, rhs in
            let leftSignal = lhs.signalStrength ?? Int.min
            let rightSignal = rhs.signalStrength ?? Int.min
            if leftSignal == rightSignal {
                return lhs.displayName < rhs.displayName
            }
            return leftSignal > rightSignal
        }

        DispatchQueue.main.async {
            self.onAdaptersChanged?(adapters)
        }
    }

    private func updateCharacteristics(for characteristics: [CBCharacteristic], peripheral: CBPeripheral) {
        for characteristic in characteristics {
            if Constants.readCharacteristicUUIDs.contains(characteristic.uuid),
               characteristic.properties.contains(.notify) || characteristic.properties.contains(.read) {
                readCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }

            if Constants.writeCharacteristicUUIDs.contains(characteristic.uuid),
               characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
            }
        }

        if readCharacteristic != nil, writeCharacteristic != nil {
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            emitState(.ready("Connected"))
        }
    }
}

extension BluetoothELM327Transport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if isScanning {
                beginScan()
            }
        case .poweredOff:
            emitState(.waiting("Bluetooth is powered off"))
        case .unauthorized:
            emitState(.unauthorized(AppError.bluetoothPermissionDenied.localizedDescription))
        case .unsupported:
            emitState(.unsupported(AppError.bluetoothUnavailable.localizedDescription))
        case .resetting:
            emitState(.waiting("Bluetooth is resetting"))
        case .unknown:
            emitState(.setup)
        @unknown default:
            emitState(.unknown("Unexpected Bluetooth state"))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard RSSI.intValue < 0 else { return }

        let identifier = peripheral.identifier.uuidString
        let descriptor = BluetoothAdapterDescriptor(
            identifier: identifier,
            name: peripheral.name ?? "Unnamed Adapter",
            signalStrength: RSSI.intValue
        )

        discoveredPeripherals[identifier] = peripheral

        if let index = discoveredAdapters.firstIndex(where: { $0.identifier == identifier }) {
            discoveredAdapters[index] = descriptor
        } else {
            discoveredAdapters.append(descriptor)
        }

        if selectedAdapter?.identifier == descriptor.identifier {
            selectedAdapter = descriptor
        }

        emitAdaptersChanged()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(Constants.supportedServices)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectTimeoutTask?.cancel()
        let message = error?.localizedDescription ?? "Failed to connect"
        emitState(.failed(message))
        onError?(error ?? AppError.transportError(message))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        readCharacteristic = nil
        writeCharacteristic = nil
        messageProcessor.reset()

        if let error {
            emitState(.failed(error.localizedDescription))
            onError?(error)
        } else {
            emitState(.disconnected)
        }
    }
}

extension BluetoothELM327Transport: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectTimeoutTask?.cancel()
            emitState(.failed(error.localizedDescription))
            onError?(error)
            return
        }

        for service in peripheral.services ?? [] {
            switch service.uuid {
            case CBUUID(string: "FFE0"):
                peripheral.discoverCharacteristics([CBUUID(string: "FFE1")], for: service)
            case CBUUID(string: "FFF0"):
                peripheral.discoverCharacteristics([CBUUID(string: "FFF1"), CBUUID(string: "FFF2")], for: service)
            case CBUUID(string: "18F0"):
                peripheral.discoverCharacteristics([CBUUID(string: "2AF0"), CBUUID(string: "2AF1")], for: service)
            default:
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectTimeoutTask?.cancel()
            emitState(.failed(error.localizedDescription))
            onError?(error)
            return
        }

        updateCharacteristics(for: service.characteristics ?? [], peripheral: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            onError?(error)
            return
        }

        guard let data = characteristic.value else { return }
        messageProcessor.processReceivedData(data)
    }
}
