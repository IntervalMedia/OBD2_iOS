import SwiftUI
import Charts

struct LiveChartView: View {
    @EnvironmentObject private var obd: OBDService
    @State private var selectedMetric: Metric = .rpm

    enum Metric: String, CaseIterable, Identifiable {
        case rpm = "RPM"
        case speed = "Speed"
        case coolant = "Coolant"
        case throttle = "Throttle"
        case voltage = "Battery"

        var id: String { rawValue }
    }

    private var chartSamples: [LiveSample] {
        Array(obd.liveSamples.suffix(60))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(Metric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedMetric.rawValue).font(.subheadline).foregroundStyle(.secondary)
                    Text(latestValueText)
                        .font(.system(.largeTitle, design: .rounded, weight: .medium))
                        .monospacedDigit()
                    Text("Latest reading · \(chartSamples.count) recent samples")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if chartSamples.isEmpty {
                    ContentUnavailableView("No readings yet", systemImage: "chart.xyaxis.line",
                        description: Text("Start polling in Live to see changes over time."))
                        .frame(minHeight: 280)
                } else {
                    Chart(chartSamples) { sample in
                        if let yValue = value(for: sample) {
                            AreaMark(x: .value("Time", sample.timestamp),
                                     y: .value(selectedMetric.rawValue, yValue))
                                .foregroundStyle(.teal.opacity(0.08))
                            LineMark(x: .value("Time", sample.timestamp),
                                     y: .value(selectedMetric.rawValue, yValue))
                                .foregroundStyle(.teal)
                                .lineStyle(.init(lineWidth: 2))
                        }
                    }
                    .chartXAxisLabel("Time")
                    .frame(height: 320)
                    .accessibilityLabel("Recent \(selectedMetric.rawValue) readings")
                }
            }
            .padding(24)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: 920)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .appScreen()
        .navigationTitle("Charts")
    }

    private func value(for sample: LiveSample) -> Double? {
        switch selectedMetric {
        case .rpm:
            return sample.rpm
        case .speed:
            return sample.speedKph.map(Double.init)
        case .coolant:
            return sample.coolantTempC.map(Double.init)
        case .throttle:
            return sample.throttlePositionPercent
        case .voltage:
            return sample.batteryVoltage
        }
    }

    private var latestValueText: String {
        guard let latest = obd.latestSample else { return "--" }

        switch selectedMetric {
        case .rpm:
            return latest.rpm.map { String(format: "%.0f rpm", $0) } ?? "--"
        case .speed:
            return latest.speedKph.map { "\($0) km/h" } ?? "--"
        case .coolant:
            return latest.coolantTempC.map { "\($0) °C" } ?? "--"
        case .throttle:
            return latest.throttlePositionPercent.map { String(format: "%.1f %%", $0) } ?? "--"
        case .voltage:
            return latest.batteryVoltage.map { String(format: "%.2f V", $0) } ?? "--"
        }
    }
}
