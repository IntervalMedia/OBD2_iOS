import SwiftUI
import UniformTypeIdentifiers

struct NissanDiagnosticsView: View {
    @EnvironmentObject private var obd: OBDService
    @EnvironmentObject private var navigation: AppNavigation
    @StateObject private var session = NissanSessionService()
    @State private var exporting = false
    @State private var confirmClear = false
    @State private var pendingLearning: NissanLearning?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                AppSectionHeading(title: "A closer look at your Nissan",
                                  subtitle: "Read manufacturer-specific data and access supported service functions.")
                    .padding(.vertical, 8)
                SessionStatusView(title: session.running ? "Nissan connected" : "Nissan diagnostics",
                                  detail: session.status, active: session.running)
                if session.busy {
                    ProgressView("Communicating with the vehicle…")
                }
                if !obd.isConnected && !session.busy {
                    Text(session.module == .engine
                         ? "Connect an adapter to read engine data, fault codes and supported service functions."
                         : "Connect an adapter to read CVT identification, calibration and counters.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Connect adapter", systemImage: "cable.connector") { navigation.showConnection() }
                        .buttonStyle(.borderedProminent)
                }
            }
            Section("Session setup") {
                Picker("Control module", selection: $session.module) {
                    ForEach(NissanModule.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(session.running || session.busy)
                if session.module == .engine {
                Picker("ECU profile", selection: $session.profile) {
                    ForEach(NissanECUProfile.allCases) { profile in
                        Text(profile.rawValue.capitalized).tag(profile)
                    }
                }
                .disabled(session.running || session.busy)
                }
                Text("Choose a module, then start a session. Nissan uses the connected adapter exclusively; ending the session disconnects it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if session.running {
            if session.module == .engine {
            Section("ECU and fault codes") {
                if let identity = session.identity {
                    Text(identity.identifier + String(format: " · family %02X", identity.family))
                        .font(.body.monospaced())
                } else { Text("Start a session to identify the engine control module.").foregroundStyle(.secondary) }
                ForEach(session.codes) { code in
                    HStack {
                        Text(code.code).font(.body.monospaced())
                        Spacer()
                        Text(String(format: "Status %02X", code.status)).foregroundStyle(.secondary)
                    }
                }
                Button("Read Nissan Fault Codes") { Task { await session.readCodes() } }
                    .disabled(!canDiagnose)
                Button("Clear Nissan Fault Codes…", role: .destructive) { confirmClear = true }
                    .disabled(!canDiagnose)
                Button("Read Supported Registers (1100)") { Task { await session.readSupportedRegisters() } }
                    .disabled(!canDiagnose)
                if let registers = session.supported {
                    Text(registers.sorted().map { String(format: "%04X", $0) }.joined(separator: ", "))
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            workSupportSection
            Section("Nissan live data") {
                ForEach(session.availableParameters) { parameter in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(parameter.rawValue, isOn: selectionBinding(parameter))
                            .disabled(session.polling || session.busy)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(session.values[parameter].map { String(format: "%.2f", $0) } ?? "—")
                                .font(.title2.weight(.medium))
                                .monospacedDigit()
                            Text(parameter.unit).foregroundStyle(.secondary)
                        }
                        if let error = session.errors[parameter] {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                Text("\(session.samples.count) records · latest 5,000 retained")
                    .font(.caption).foregroundStyle(.secondary)
            }
            } else {
                cvtSection
            }
            }
            if !session.samples.isEmpty {
            Section("Export") {
                Button("Export Nissan CSV") { exporting = true }
                    .disabled(session.samples.isEmpty)
                if let exportError { Text(exportError).foregroundStyle(.red) }
                Text("Export the latest 5,000 readings. Adapter messages are available in Tools → Activity. Throttle readings show sensor voltage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
        }
        .appScreen()
        .navigationTitle("Nissan")
        .appBottomBar {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { sessionControls }
                VStack(spacing: 12) { sessionControls }
            }
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Clear Nissan fault codes?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Fault Codes", role: .destructive) { Task { await session.clearCodes() } }
        } message: {
            Text("This sends one ECU clear request and can erase stored diagnostic information. Read codes first. A missing response will not trigger a retry.")
        }
        .confirmationDialog(pendingLearning?.title ?? "Work support", isPresented: Binding(
            get: { pendingLearning != nil }, set: { if !$0 { pendingLearning = nil } }
        ), titleVisibility: .visible) {
            if let learning = pendingLearning {
                Button("Run \(learning.title)", role: .destructive) {
                    pendingLearning = nil
                    Task { await session.performLearning(learning) }
                }
            }
        } message: {
            Text("This changes ECU learned values. Confirm that the vehicle-specific service procedure's engine, temperature, transmission and electrical-load conditions are met. Keep the vehicle stationary and the adapter connected. Allow up to 120 seconds, then turn ignition off for at least 10 seconds. The start command will not be retried.")
        }
        .fileExporter(isPresented: $exporting,
                      document: NissanCSVDocument(text: NissanCSVExporter.makeCSV(samples: session.samples)),
                      contentType: .commaSeparatedText,
                      defaultFilename: "nissan-live") { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
            else { exportError = nil }
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        Button(session.running ? "End session" : "Start session",
               systemImage: session.running ? "power" : "link") {
            Task {
                if session.running { await session.stop() }
                else { await session.start(using: obd) }
            }
        }
        .appChromeButton(prominent: !session.running)
        .disabled(session.busy || (!session.running && !obd.isConnected))
        if session.module == .engine {
        Button(session.polling ? "Stop logging" : "Log live data",
               systemImage: session.polling ? "stop" : "waveform.path") {
            Task {
                if session.polling { await session.stopLogging() }
                else { session.startLogging() }
            }
        }
        .appChromeButton(prominent: session.running && !session.polling)
        .disabled(!session.running || session.busy)
        }
    }

    @ViewBuilder
    private var workSupportSection: some View {
        Section("Engine work support · CAN") {
            Button("Read supported functions") { Task { await session.discoverWorkSupport() } }
                .disabled(!canDiagnose || session.profile != .petrol)
            if let support = session.workSupport {
                Text("Active test IDs: " + hexList(support.activeTests))
                Text("Learning IDs: " + hexList(support.learnings))
                Text("Correction IDs: " + hexList(support.corrections))
                ForEach(NissanLearning.allCases, id: \.self) { learning in
                    Button(learning.title + "…") { pendingLearning = learning }
                        .disabled(!canDiagnose || !support.learnings.contains(learning.rawValue))
                }
                if support.learnings.contains(4) {
                    Text("Closed-throttle learning is reported by this ECU. Execution is unavailable because its completion response has not been established.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Capability discovery does not run active tests or corrections. Learning is available only for supported petrol CAN engine sessions. Follow the vehicle service procedure before starting.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cvtSection: some View {
        Section("CVT information · CAN") {
            if let info = session.cvtInformation {
                LabeledContent("ECU", value: info.identifier)
                LabeledContent("Calibration IDs", value: info.calibrationIDs.joined(separator: " · "))
                LabeledContent("Fluid deterioration counter", value: String(info.deteriorationCounter))
                LabeledContent("CVT-A", value: String(info.cvtA))
                LabeledContent("CVT-B", value: String(info.cvtB))
                LabeledContent("HCOUNT", value: String(info.highTemperatureCount))
                LabeledContent("HHCOUNT", value: String(info.veryHighTemperatureCount))
            }
            Button("Read CVT information") { Task { await session.readCVTInformation() } }
                .disabled(!session.running || session.busy)
            Text("Read-only information from compatible NC3 CVT modules. Counter values are not an oil-life percentage or a maintenance recommendation. Register-based CVT variants and NC1 adapters are not supported.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func hexList(_ ids: Set<UInt8>) -> String {
        ids.isEmpty ? "None reported" : ids.sorted().map { String(format: "%02X", $0) }.joined(separator: ", ")
    }

    private var canDiagnose: Bool { session.running && !session.busy }

    private func selectionBinding(_ parameter: NissanParameter) -> Binding<Bool> {
        Binding(get: { session.selected.contains(parameter) }, set: { enabled in
            session.selected = enabled ? session.selected.union([parameter]) : session.selected.subtracting([parameter])
        })
    }
}

private struct NissanCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
