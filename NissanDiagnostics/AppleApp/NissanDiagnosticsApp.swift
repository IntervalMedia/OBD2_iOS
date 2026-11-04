import SwiftUI
import UniformTypeIdentifiers
import NissanCore

@main
struct NissanDiagnosticsApp: App {
    var body: some Scene { WindowGroup { Dashboard() } }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var host = "192.168.0.10"
    @Published var port = "35000"
    @Published var demo = true
    @Published var status = "Disconnected"
    @Published var running = false
    @Published var values: [String: Double] = [:]
    @Published var selected = Set(NissanParameter.allCases.map(\.rawValue))
    @Published var transcript = ""
    @Published var ecu = "Not identified"
    @Published var codes: [TroubleCode] = []
    @Published var codeStatus = "Connect to read fault codes."
    @Published var unavailable: Set<String> = []
    private(set) var sessionDemo = true
    private var task: Task<Void, Never>?
    private var transport: TCPTransport?
    private var samples = "timestamp,source,parameter,value,unit\n"
    var csv: String { samples }

    func connect() {
        guard task == nil else { return }
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard demo || (!cleanHost.isEmpty && UInt16(port).map { $0 > 0 } == true) else {
            status = "Enter an adapter host and port between 1 and 65535."
            return
        }
        let useDemo = demo
        sessionDemo = useDemo
        unavailable = []
        codes = []
        ecu = useDemo ? "Simulated petrol ECM" : "Not identified"
        codeStatus = useDemo ? "Demo — no vehicle fault codes read" : "Reading ECU…"
        running = true
        values = [:]
        samples = "timestamp,source,parameter,value,unit\n"
        task = Task {
            var client: DiagnosticClient?
            do {
                if !useDemo {
                    let tcp = TCPTransport(host: cleanHost, port: UInt16(port)!)
                    transport = tcp
                    let logged = LoggedTransport(base: tcp) { [weak self] entry in
                        Task { @MainActor in
                            guard let self else { return }
                            self.transcript = String((self.transcript + entry + "\n").suffix(48_000))
                        }
                    }
                    let connected = DiagnosticClient(transport: logged)
                    status = "Initializing adapter…"
                    try await connected.initialize()
                    client = connected
                    do {
                        let identity = try await connected.identifyECU()
                        ecu = identity.identifier + String(format: " · family %02X", identity.family)
                        codes = try await connected.readTroubleCodes()
                        codeStatus = codes.isEmpty ? "No stored fault codes reported." : "Stored fault codes"
                    } catch {
                        try Task.checkCancellation()
                        codeStatus = "ECU identification or fault-code read unavailable: " + error.localizedDescription
                    }
                }
                if let client { try await client.prepareDataLogging() }
                status = useDemo ? "DEMO — simulated values" : "Connected — read-only monitoring"
                var tick = 0.0
                while !Task.isCancelled {
                    for (index, parameter) in NissanParameter.allCases.enumerated() where selected.contains(parameter.rawValue) && !unavailable.contains(parameter.rawValue) {
                        try Task.checkCancellation()
                        let value: Double
                        if let client {
                            do { value = try await client.read(parameter: parameter) }
                            catch let error as DiagnosticError {
                                switch error {
                                case .negativeResponse, .adapter, .unexpectedResponse, .malformedResponse:
                                    unavailable = unavailable.union([parameter.rawValue])
                                    transcript = String((transcript + "\nUnavailable: " + parameter.rawValue + " — " + error.localizedDescription).suffix(48_000))
                                    continue
                                default: throw error
                                }
                            }
                        }
                        else { value = Double(index + 1) * 10 + sin(tick) * 2 }
                        values[parameter.rawValue] = value
                        let safeName = parameter.rawValue.replacingOccurrences(of: "\"", with: "\"\"")
                        let safeUnit = parameter.unit.replacingOccurrences(of: "\"", with: "\"\"")
                        samples += "\(Date().ISO8601Format()),\(useDemo ? "demo" : "live"),\"\(safeName)\",\(value),\"\(safeUnit)\"\n"
                        if samples.utf8.count > 2_000_000 { samples = "timestamp,source,parameter,value,unit\n"; status = "Recording restarted at 2 MB limit" }
                    }
                    tick += 0.25
                    try await Task.sleep(for: .seconds(1))
                }
            } catch is CancellationError { status = "Disconnected" }
            catch { status = Task.isCancelled ? "Disconnected" : error.localizedDescription }
            await transport?.close()
            transport = nil
            running = false
            task = nil
        }
    }

    func disconnect() { task?.cancel() }
}

private struct LoggedTransport: ELMTransport {
    let base: TCPTransport
    let log: @Sendable (String) -> Void
    func exchange(_ command: String) async throws -> String {
        log("> " + command)
        let response = try await base.exchange(command)
        log("< " + response)
        return response
    }
    func exchange(_ command: String, timeout: TimeInterval) async throws -> String {
        log("> " + command)
        let response = try await base.exchange(command, timeout: timeout)
        log("< " + response)
        return response
    }
    func close() async { await base.close() }
}

struct Dashboard: View {
    @StateObject private var model = DashboardModel()
    @State private var exporting = false
    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    Toggle("Demo (simulated data)", isOn: $model.demo).disabled(model.running)
                    if !model.demo {
                        TextField("Wi-Fi adapter host", text: $model.host).autocorrectionDisabled().disabled(model.running)
                        TextField("TCP port", text: $model.port).disabled(model.running)
                        Text("Join your ELM327 Wi-Fi adapter network first. Bluetooth Classic serial adapters are not supported by this app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(model.running ? "Disconnect" : "Connect") {
                        if model.running { model.disconnect() } else { model.connect() }
                    }
                    Text(model.status).font(.callout).accessibilityLabel("Connection status: " + model.status)
                }
                Section("ECU and fault codes") {
                    Text(model.ecu)
                    Text(model.codeStatus).font(.caption).foregroundStyle(.secondary)
                    ForEach(model.codes) { code in Text(code.code).font(.system(.body, design: .monospaced)) }
                }
                Section(model.demo ? "Live data — DEMO" : "Nissan petrol ECM live data") {
                    ForEach(Array(NissanParameter.allCases), id: \.rawValue) { parameter in
                        HStack {
                            Toggle(isOn: Binding(get: { model.selected.contains(parameter.rawValue) }, set: { enabled in
                                var selected = model.selected
                                if enabled { selected.insert(parameter.rawValue) } else { selected.remove(parameter.rawValue) }
                                model.selected = selected
                            })) { Text(parameter.rawValue) }
                            Spacer()
                            Text(model.unavailable.contains(parameter.rawValue) ? "Unavailable" : model.values[parameter.rawValue].map { String(format: "%.2f", $0) } ?? "—")
                                .monospacedDigit()
                            Text(parameter.unit).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Adapter transcript") {
                    Text(model.transcript.isEmpty ? "Raw commands and responses appear here when connected to hardware." : model.transcript)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Section {
                    Text("Read-only monitoring using a statically recovered petrol ECM profile. Diesel profiles are not included. Nissan support depends on ECU, model year, and adapter. Hardware compatibility has not been validated. Use while parked.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nissan Diagnostics")
            .toolbar { Button("Export CSV") { exporting = true } }
            .fileExporter(isPresented: $exporting, document: CSVDocument(text: model.csv), contentType: .commaSeparatedText, defaultFilename: model.sessionDemo ? "nissan-demo" : "nissan-live") { result in
                if case .failure(let error) = result { model.status = "Export failed: " + error.localizedDescription }
            }
            .onDisappear { model.disconnect() }
        }
        .frame(minWidth: 340, minHeight: 500)
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
