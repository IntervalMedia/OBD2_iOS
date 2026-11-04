import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var obd: OBDService
    @EnvironmentObject private var navigation: AppNavigation
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                AppSectionHeading(title: "Understand the warning", subtitle: "Read stored engine fault codes before deciding what to do next.")
                SessionStatusView(
                    title: obd.isNissanSessionActive ? "Nissan session active" : canDiagnose ? "Ready to check" : "Connect your vehicle",
                    detail: obd.isNissanSessionActive
                        ? "Read manufacturer-specific codes from the Nissan screen."
                        : canDiagnose ? "Standard OBD-II · stored fault codes"
                        : "Set up the adapter connection first. Your next step is below.",
                    active: canDiagnose
                )
                Divider()
                resultContent
                if let error = obd.diagnosticError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("A fault code identifies a detected condition, not necessarily a part to replace. Save the results before clearing codes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 760)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .appScreen()
        .navigationTitle("Diagnostics")
        .appBottomBar {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }
                VStack(spacing: 12) { actions }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Clear stored fault codes?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear fault codes", role: .destructive) { Task { await obd.clearDTCs() } }
        } message: {
            Text("This erases stored diagnostic information and may reset readiness monitors. Clearing a code does not repair its cause. Save the codes first.")
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if obd.isReadingDTCs || obd.isClearingDTCs {
            HStack(spacing: 14) {
                ProgressView()
                VStack(alignment: .leading, spacing: 5) {
                    Text(obd.isClearingDTCs ? "Clearing stored codes" : "Checking your vehicle")
                        .font(.headline)
                    Text("Waiting for the ECU response. Keep the adapter connected.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else if obd.hasReadDTCs && obd.dtcs.isEmpty {
            resultMessage("No stored codes reported", detail: "The ECU returned no stored OBD-II fault codes. This is not a complete vehicle health check.", icon: "checkmark", tint: .appAccent)
        } else if obd.dtcs.isEmpty {
            resultMessage("Start with a code check", detail: "Stored codes will appear here after a successful read.", icon: "wrench.and.screwdriver", tint: .secondary)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(obd.dtcs.count) STORED \(obd.dtcs.count == 1 ? "CODE" : "CODES")")
                    .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                ForEach(obd.dtcs) { dtc in
                    HStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(dtc.code).font(.system(.title2, design: .monospaced, weight: .medium))
                            .textSelection(.enabled)
                        Spacer()
                        Text("Stored").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func resultMessage(_ title: String, detail: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon).font(.title).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3.weight(.medium))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var canDiagnose: Bool { obd.isInitialized && !obd.isNissanSessionActive }
    private var busy: Bool { obd.isReadingDTCs || obd.isClearingDTCs }

    @ViewBuilder
    private var actions: some View {
        if obd.isNissanSessionActive {
            Text("Open Nissan to continue this session.").font(.subheadline).foregroundStyle(.secondary)
        } else if !canDiagnose {
            Button("Set up connection", systemImage: "link") { navigation.showConnection() }
                .appChromeButton(prominent: true)
        } else {
            if obd.hasReadDTCs && !obd.dtcs.isEmpty {
                Button("Clear codes", systemImage: "trash", role: .destructive) { confirmClear = true }
                    .appChromeButton().disabled(busy)
            }
            Button(obd.hasReadDTCs ? "Read again" : "Read fault codes", systemImage: "arrow.clockwise") {
                Task { await obd.readDTCs() }
            }
            .appChromeButton(prominent: true).disabled(busy)
        }
    }
}
