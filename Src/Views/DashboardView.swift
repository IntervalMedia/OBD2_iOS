import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var obd: OBDService
    @EnvironmentObject private var navigation: AppNavigation
    @StateObject private var viewModel = DashboardViewModel()
    @State private var confirmClear = false
    @ScaledMetric(relativeTo: .largeTitle) private var engineFontSize = 64.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                AppSectionHeading(title: "Your car, at a glance", subtitle: sessionDetail)
                readingStatus
                engineReading
                metricsGrid
                Text("A dash means no value was received. Recorded readings remain available when disconnected.")
                    .font(.caption).foregroundStyle(.secondary)
                sessionArchive
            }
            .frame(maxWidth: 920)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .appScreen()
        .navigationTitle("Live")
        .appBottomBar {
            primaryAction
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Clear recorded samples?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear samples", role: .destructive) { obd.clearSamples() }
        }
    }

    private var readingStatus: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                collectionLabel
                Spacer()
                sampleTimestamp
            }
            VStack(alignment: .leading, spacing: 8) {
                collectionLabel
                sampleTimestamp
            }
        }
        .font(.caption.weight(.medium))
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(.quaternary).frame(height: 1) }
    }

    private var collectionLabel: some View {
        Label(obd.isPolling ? "COLLECTING READINGS" : obd.latestSample == nil ? "NO READINGS YET" : "RECORDED READINGS",
              systemImage: obd.isPolling ? "waveform.path" : "clock")
            .foregroundStyle(obd.isPolling ? Color.appAccent : Color.secondary)
    }

    @ViewBuilder
    private var sampleTimestamp: some View {
        if let sample = obd.latestSample {
            Text(sample.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Last reading \(sample.timestamp.formatted())")
        } else {
            Text("Waiting for your first reading").foregroundStyle(.secondary)
        }
    }

    private var engineReading: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("ENGINE SPEED").font(.caption.weight(.semibold)).tracking(1.5)
                Spacer()
                Image(systemName: "gauge.with.dots.needle.50percent").foregroundStyle(Color.appAccent)
                    .accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { engineValue }
                VStack(alignment: .leading, spacing: 8) { engineValue }
            }
            Rectangle().fill(Color.appAccent).frame(width: 40, height: 3)
                .accessibilityHidden(true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var engineValue: some View {
        Text(obd.latestSample?.rpm.map { String(format: "%.0f", $0) } ?? "—")
            .font(.system(size: engineFontSize, weight: .light, design: .monospaced))
            .lineLimit(1).minimumScaleFactor(0.5)
        Text("rpm").font(.title3).foregroundStyle(.secondary)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
            metric("Road speed", value: obd.latestSample?.speedKph.map(String.init) ?? "—", unit: "km/h", icon: "speedometer")
            metric("Coolant", value: obd.latestSample?.coolantTempC.map(String.init) ?? "—", unit: "°C", icon: "thermometer.medium")
            metric("Throttle", value: obd.latestSample?.throttlePositionPercent.map { String(format: "%.1f", $0) } ?? "—", unit: "%", icon: "slider.horizontal.3")
            metric("Adapter voltage", value: obd.latestSample?.batteryVoltage.map { String(format: "%.2f", $0) } ?? "—", unit: "V", icon: "battery.100")
        }
    }

    private func metric(_ title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.system(.largeTitle, design: .monospaced, weight: .regular))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(18)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var sessionArchive: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    archiveLabel
                    Spacer()
                    chartLink
                }
                VStack(alignment: .leading, spacing: 12) { archiveLabel; chartLink }
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { dataActions }
                VStack(alignment: .leading, spacing: 12) { dataActions }
            }
            .buttonStyle(.bordered)
            if let error = viewModel.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var archiveLabel: some View {
        Text("\(obd.liveSamples.count) saved samples").font(.subheadline.weight(.medium))
    }

    private var chartLink: some View {
        NavigationLink { LiveChartView() } label: {
            Label("Explore charts", systemImage: "chart.xyaxis.line")
        }.font(.subheadline)
    }

    @ViewBuilder
    private var dataActions: some View {
        Button("Export CSV", systemImage: "square.and.arrow.up") { viewModel.exportCSV(using: obd) }
            .disabled(obd.liveSamples.isEmpty)
        if let url = viewModel.exportURL { ShareLink("Share", item: url) }
        Button("Clear samples", systemImage: "trash") { confirmClear = true }
            .disabled(obd.liveSamples.isEmpty)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if obd.isNissanSessionActive {
            Text("Nissan session active · readings are available in Nissan.")
                .font(.subheadline).foregroundStyle(.secondary)
        } else if !obd.isInitialized {
            Button("Set up connection", systemImage: "link") { navigation.showConnection() }
                .appChromeButton(prominent: true)
        } else {
            Button(obd.isPolling ? "Pause readings" : "Start readings", systemImage: obd.isPolling ? "pause" : "play") {
                if obd.isPolling { obd.stopPolling() } else { obd.startPolling() }
            }
            .appChromeButton(prominent: true)
        }
    }

    private var sessionDetail: String {
        if obd.isNissanSessionActive { return "Your adapter is reserved for Nissan diagnostics." }
        if obd.isPolling { return "Readings update as your vehicle responds." }
        if obd.isInitialized { return "Vehicle connected. Start readings when you’re ready." }
        return "Connect your adapter to see what’s happening under the bonnet."
    }
}
