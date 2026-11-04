import SwiftUI

/// Setup is a progression, not a collection of adapter commands.
struct ConnectionView: View {
    @EnvironmentObject private var obd: OBDService
    @EnvironmentObject private var navigation: AppNavigation
    @State private var showNetworkSettings = false
    private enum AddressField { case host, port }
    @FocusState private var focusedField: AddressField?

    private var working: Bool { obd.isConnecting || obd.isInitializing }
    private var locked: Bool { working || obd.isConnected || obd.isNissanSessionActive }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introduction
                if obd.isNissanSessionActive {
                    reservedSession
                } else {
                    progressRail
                    if obd.isInitialized {
                        readyContent
                    } else {
                        preparation
                        adapterSelection
                        if let error = obd.connectionError { recovery(error).id("connectionRecovery") }
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: obd.connectionError) { _, error in
            if error != nil { proxy.scrollTo("connectionRecovery", anchor: .bottom) }
        }
        }
        .appScreen()
        .navigationTitle("Connect")
        .appBottomBar {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { setupActions }
                VStack(spacing: 12) { setupActions }
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                Text("VEHICLE LINK").tracking(2)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appAccent)
            Text(obd.isNissanSessionActive ? "Nissan session active" : obd.isInitialized ? "Your vehicle is ready." : "A clear connection.")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(obd.isInitialized
                 ? "Communication is confirmed. Choose what you want to explore."
                 : "Plug in your adapter. We’ll take care of the connection checks.")
                .font(.body).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    compactStage(1, title: "Prepare", complete: obd.isConnected, active: !obd.isConnected && !working)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                    compactStage(2, title: "Connect", complete: obd.isConnected, active: obd.isConnecting)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                    compactStage(3, title: "Verify", complete: obd.isInitialized, active: obd.isInitializing)
                }
                VStack(spacing: 0) {
            stage(1, title: "Prepare", detail: "Adapter powered · ignition on", complete: obd.isConnected, active: !obd.isConnected && !working)
            stage(2, title: "Connect", detail: obd.isConnecting ? "Finding your adapter…" : "Link to your adapter", complete: obd.isConnected, active: obd.isConnecting)
            stage(3, title: "Verify", detail: verificationDetail, complete: obd.isInitialized, active: obd.isInitializing)
                }
            }
            if working {
                ProgressView(obd.isConnecting ? "Finding your adapter…" : verificationDetail)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private func compactStage(_ number: Int, title: String, complete: Bool, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(complete ? "✓" : String(format: "%02d", number))
                .font(.system(.caption, design: .monospaced, weight: .semibold))
            Text(title).font(.subheadline.weight(active || complete ? .semibold : .regular))
        }
        .foregroundStyle(active || complete ? Color.appAccent : Color.secondary)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number), \(title), \(complete ? "complete" : active ? "current" : "up next")")
    }

    private func stage(_ number: Int, title: String, detail: String, complete: Bool, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(complete || active ? Color.appAccent.opacity(0.12) : Color.secondary.opacity(0.08))
                if complete {
                    Image(systemName: "checkmark").font(.subheadline.weight(.semibold))
                } else {
                    Text(String(format: "%02d", number)).font(.system(.subheadline, design: .monospaced, weight: .medium))
                }
            }
            .foregroundStyle(complete || active ? Color.appAccent : Color.secondary)
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if active && working { ProgressView().controlSize(.small).accessibilityLabel("In progress") }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title), \(complete ? "complete" : active ? "current" : "up next"), \(detail)")
    }

    private var verificationDetail: String {
        if obd.isInitialized { return "Vehicle communication confirmed" }
        if case let .initializing(step, total) = obd.connectionPhase {
            return "Preparing adapter · \(step) of \(total)"
        }
        return "Initialize adapter and check vehicle response"
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Before you connect")
            Label("Park safely and plug the adapter into the OBD port.", systemImage: "car.side")
            Label("Turn the ignition on so the vehicle can respond.", systemImage: "key.horizontal")
            if obd.settings.transportType == .wifi {
                Label("Join your adapter’s Wi-Fi in system settings. It may show “No Internet”.", systemImage: "wifi")
            } else {
                Label("Keep the adapter nearby and enable Bluetooth.", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var adapterSelection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider()
            sectionLabel("Your adapter")
            Picker("Connection type", selection: $obd.settings.transportType) {
                Text("Wi-Fi").tag(ConnectionSettings.TransportType.wifi)
                Text("Bluetooth LE").tag(ConnectionSettings.TransportType.bluetoothLE)
            }
            .pickerStyle(.segmented)
            .disabled(locked)
            if obd.settings.transportType == .wifi {
                VStack(alignment: .leading, spacing: 12) {
                    Label("\(obd.settings.host):\(String(obd.settings.port))", systemImage: "network")
                        .font(.body.monospaced()).textSelection(.enabled)
                    DisclosureGroup("Adapter address", isExpanded: $showNetworkSettings) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Use the address supplied with your adapter.")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("Host address", text: $obd.settings.host)
                                .focused($focusedField, equals: .host)
                                .textFieldStyle(.roundedBorder).adapterHostInput().autocorrectionDisabled()
                                .accessibilityLabel("Adapter host address")
                            TextField("Port", value: Binding(get: { Int(obd.settings.port) }, set: {
                                obd.settings.port = UInt16(clamping: $0)
                            }), format: .number.grouping(.never))
                                .focused($focusedField, equals: .port)
                                .textFieldStyle(.roundedBorder).adapterPortInput()
                                .accessibilityLabel("Adapter port")
                        }.padding(.top, 12)
                    }
                    .disabled(locked)
                }
            } else {
                bluetoothSelection
            }
            Text(obd.settings.transportType == .wifi
                 ? "Allow Local Network access when asked. If access is blocked, enable it for OBDMVP in system settings."
                 : "Allow Bluetooth access when asked. Only compatible Bluetooth LE adapters are supported.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !working {
                DisclosureGroup("Using Nissan diagnostics?") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connect the adapter here, then start an engine or CVT session in Nissan. That screen performs its own vehicle initialization.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if obd.isConnected {
                            Button("Continue in Nissan", systemImage: "arrow.right") { navigation.showNissan() }
                        } else {
                            Button("Connect for Nissan", systemImage: "link") { focusedField = nil; obd.connect() }
                                .disabled(obd.isScanningBluetoothAdapters || (obd.settings.transportType == .bluetoothLE && obd.selectedBluetoothAdapter == nil))
                        }
                    }.padding(.top, 12).buttonStyle(.bordered).controlSize(.large)
                }
            }
        }
    }

    private var bluetoothSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = obd.selectedBluetoothAdapter {
                Label(selected.displayName, systemImage: "checkmark").font(.headline)
            }
            Button(obd.isScanningBluetoothAdapters ? "Scanning…" : "Find adapters", systemImage: "antenna.radiowaves.left.and.right") {
                Task { await obd.scanForBluetoothAdapters() }
            }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(locked || obd.isScanningBluetoothAdapters)
            if obd.isScanningBluetoothAdapters {
                ProgressView("Looking for nearby adapters…").font(.subheadline)
            } else if obd.bluetoothAdapters.isEmpty {
                Text("No nearby adapters listed. Power on your adapter, then choose Find adapters.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(obd.bluetoothAdapters) { adapter in
                Button { obd.selectBluetoothAdapter(adapter) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(adapter.displayName).font(.headline)
                            if let strength = adapter.signalStrength {
                                Text("Signal \(strength) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: adapter.id == obd.selectedBluetoothAdapter?.id ? "checkmark" : "plus")
                    }
                    .padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(locked)
                .accessibilityAddTraits(adapter.id == obd.selectedBluetoothAdapter?.id ? .isSelected : [])
            }
        }
    }

    private func recovery(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connection needs attention", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error).font(.subheadline)
            Text("Check adapter power, ignition and network access, then try again.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Divider()
            sectionLabel("Next up")
            Button { navigation.showLive() } label: {
                destination("Live readings", detail: "Engine, speed, temperature and more", icon: "waveform.path")
            }.buttonStyle(.plain)
            Divider()
            Button { navigation.showDiagnostics() } label: {
                destination("Fault codes", detail: "Read stored diagnostic information", icon: "wrench.and.screwdriver")
            }.buttonStyle(.plain)
            Divider()
            Button { navigation.showNissan() } label: {
                destination("Nissan diagnostics", detail: "Engine work support and CVT information", icon: "car.side")
            }.buttonStyle(.plain)
        }
    }

    private var reservedSession: some View {
        VStack(alignment: .leading, spacing: 16) {
            SessionStatusView(title: "Connection reserved", detail: "Continue in Nissan. End that session before returning to standard OBD-II readings.", active: true)
            Button("Open Nissan", systemImage: "arrow.right") { navigation.showNissan() }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }

    private func destination(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).foregroundStyle(Color.appAccent).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
        }
        .padding(.vertical, 8).contentShape(Rectangle())
    }

    @ViewBuilder private var setupActions: some View {
        if obd.isNissanSessionActive {
            Button("Continue in Nissan", systemImage: "arrow.right") { navigation.showNissan() }
                .appChromeButton(prominent: true)
        } else if working {
            Button("Cancel connection", systemImage: "xmark") { obd.disconnect() }.appChromeButton()
        } else if obd.isInitialized {
            Button("Disconnect", systemImage: "power") { obd.disconnect() }.appChromeButton()
            Button("Open live readings", systemImage: "arrow.right") { navigation.showLive() }.appChromeButton(prominent: true)
        } else {
            if obd.isConnected {
                Button("Disconnect", systemImage: "power") { obd.disconnect() }.appChromeButton()
            }
            Button(obd.connectionError == nil ? "Connect & prepare" : "Try again", systemImage: "link") {
                focusedField = nil
                obd.connectAndInitialize()
            }
            .appChromeButton(prominent: true)
            .disabled(obd.isScanningBluetoothAdapters || (obd.settings.transportType == .bluetoothLE && obd.selectedBluetoothAdapter == nil))
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
    }
}
