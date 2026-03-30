import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var obd: OBDService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                transportCard
                connectionCard
                actionCard
            }
            .padding()
        }
        .navigationTitle("Connection")
        .background(Color(.systemGroupedBackground))
    }

    private var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                labelValue("Transport", transportDisplayName)
                labelValue("State", obd.connectionStateDescription)
                labelValue("Initialized", obd.isInitialized ? "Yes" : "No")
                labelValue("VIN", obd.vehicleInfo.vin ?? "Unavailable")
                if obd.settings.transportType == .bluetoothLE {
                    labelValue("Selected Adapter", selectedBluetoothAdapterDisplayName)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Adapter Status", systemImage: "dot.radiowaves.left.and.right")
        }
    }

    private var transportCard: some View {
        GroupBox {
            Picker("Transport", selection: transportBinding) {
                Text("Wi-Fi").tag(ConnectionSettings.TransportType.wifi)
                Text("Bluetooth LE").tag(ConnectionSettings.TransportType.bluetoothLE)
            }
            .pickerStyle(.segmented)
        } label: {
            Label("Connection Type", systemImage: "arrow.left.arrow.right")
        }
    }

    private var connectionCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                switch obd.settings.transportType {
                case .wifi:
                    wifiConnectionFields
                case .bluetoothLE:
                    bluetoothConnectionFields
                }
            }
        } label: {
            Label(connectionCardTitle, systemImage: connectionCardSystemImage)
        }
    }

    private var wifiConnectionFields: some View {
        VStack(spacing: 12) {
            TextField("Host", text: Binding(
                get: { obd.settings.host },
                set: { obd.settings.host = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            TextField("Port", value: Binding(
                get: { Int(obd.settings.port) },
                set: { newValue in
                    obd.settings.port = Self.clampedPort(from: newValue)
                }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.numberPad)
        }
    }

    private var bluetoothConnectionFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task { await obd.scanForBluetoothAdapters() }
                } label: {
                    Label(obd.isScanningBluetoothAdapters ? "Scanning..." : "Scan for Adapters", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(obd.isScanningBluetoothAdapters)

                if obd.isScanningBluetoothAdapters {
                    ProgressView()
                }
            }

            if obd.bluetoothAdapters.isEmpty {
                emptyBluetoothState
            } else {
                VStack(spacing: 8) {
                    ForEach(obd.bluetoothAdapters) { adapter in
                        Button {
                            obd.selectBluetoothAdapter(adapter)
                        } label: {
                            bluetoothAdapterRow(adapter)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyBluetoothState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Bluetooth LE adapters found yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Tap Scan to discover compatible ELM327 adapters.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func bluetoothAdapterRow(_ adapter: BluetoothAdapterDescriptor) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(adapter.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(adapter.identifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let signalStrength = adapter.signalStrength {
                    Text("RSSI \(signalStrength) dBm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if adapter.id == obd.selectedBluetoothAdapter?.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.accent)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                Button("Connect") { obd.connect() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                Button("Initialize Adapter") {
                    Task { await obd.initializeAdapter() }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Read VIN") {
                    Task { await obd.readVIN() }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Disconnect", role: .destructive) {
                    obd.disconnect()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        } label: {
            Label("Actions", systemImage: "bolt.horizontal.circle")
        }
    }

    private func labelValue(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    private var transportBinding: Binding<ConnectionSettings.TransportType> {
        Binding(
            get: { obd.settings.transportType },
            set: { obd.settings.transportType = $0 }
        )
    }

    private var transportDisplayName: String {
        switch obd.settings.transportType {
        case .wifi:
            return "Wi-Fi"
        case .bluetoothLE:
            return "Bluetooth LE"
        }
    }

    private var connectionCardTitle: String {
        switch obd.settings.transportType {
        case .wifi:
            return "Network"
        case .bluetoothLE:
            return "Bluetooth LE"
        }
    }

    private var connectionCardSystemImage: String {
        switch obd.settings.transportType {
        case .wifi:
            return "network"
        case .bluetoothLE:
            return "dot.radiowaves.left.and.right"
        }
    }

    private var selectedBluetoothAdapterDisplayName: String {
        obd.selectedBluetoothAdapter?.displayName ?? "None selected"
    }

    private static func clampedPort(from value: Int?) -> UInt16 {
        guard let value else { return 35000 }
        let clamped = min(max(value, 0), Int(UInt16.max))
        return UInt16(clamped)
    }
}
