import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var obd: OBDService
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                topSummary
                metricsGrid
                controlPanel
                exportPanel
            }
            .padding()
        }
        .navigationTitle("Live Dashboard")
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showShareSheet) {
            if let url = viewModel.exportURL {
                ActivityViewController(activityItems: [url])
            }
        }
    }

    private var topSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(obd.isConnected ? "Connected" : "Disconnected")
                    .font(.title2.weight(.semibold))
                Text(obd.isInitialized ? "Adapter initialized and ready for standard OBD-II polling." : "Initialize the adapter before starting live polling.")
                    .foregroundStyle(.secondary)
                HStack {
                    summaryBadge(title: "Samples", value: "\(obd.liveSamples.count)")
                    summaryBadge(title: "State", value: obd.connectionStateDescription)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Session", systemImage: "car.front.waves.up")
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCard(title: "RPM", value: obd.latestSample?.rpm.map { String(format: "%.0f", $0) } ?? "--", unit: "rpm", systemImage: "gauge.open.with.lines.needle.33percent")
            metricCard(title: "Speed", value: obd.latestSample?.speedKph.map(String.init) ?? "--", unit: "km/h", systemImage: "speedometer")
            metricCard(title: "Coolant", value: obd.latestSample?.coolantTempC.map(String.init) ?? "--", unit: "°C", systemImage: "thermometer.medium")
            metricCard(title: "Throttle", value: obd.latestSample?.throttlePositionPercent.map { String(format: "%.1f", $0) } ?? "--", unit: "%", systemImage: "slider.horizontal.3")
            metricCard(title: "Battery", value: obd.latestSample?.batteryVoltage.map { String(format: "%.2f", $0) } ?? "--", unit: "V", systemImage: "battery.100")
            metricCard(title: "VIN", value: obd.vehicleInfo.vin ?? "--", unit: "", systemImage: "number")
        }
    }

    private var controlPanel: some View {
        GroupBox {
            VStack(spacing: 12) {
                Button("Start Live Polling") {
                    obd.startPolling()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                HStack {
                    Button("Stop Polling", role: .destructive) {
                        obd.stopPolling()
                    }
                    .buttonStyle(.bordered)

                    Button("Clear Samples") {
                        obd.clearSamples()
                    }
                    .buttonStyle(.bordered)
                }
            }
        } label: {
            Label("Controls", systemImage: "playpause")
        }
    }

    private var exportPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Button("Export CSV") {
                    viewModel.exportCSV(using: obd)
                    showShareSheet = viewModel.exportURL != nil
                }
                .buttonStyle(.bordered)

                if let error = viewModel.lastErrorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    private func metricCard(title: String, value: String, unit: String, systemImage: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        }
    }

    private func summaryBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
