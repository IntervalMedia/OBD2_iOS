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
        VStack(spacing: 16) {
            Picker("Metric", selection: $selectedMetric) {
                ForEach(Metric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if chartSamples.isEmpty {
                emptyStateView
            } else {
                Chart(chartSamples) { sample in
                    if let yValue = value(for: sample) {
                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            y: .value(selectedMetric.rawValue, yValue)
                        )
                        .opacity(0.15)

                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value(selectedMetric.rawValue, yValue)
                        )
                        .lineStyle(.init(lineWidth: 2))

                        PointMark(
                            x: .value("Time", sample.timestamp),
                            y: .value(selectedMetric.rawValue, yValue)
                        )
                    }
                }
                .frame(height: 300)
                .padding(.horizontal)
            }

            List {
                Section("Chart Details") {
                    Text("Metric: \(selectedMetric.rawValue)")
                    Text("Points shown: \(chartSamples.count)")
                }

                Section("Latest") {
                    Text(latestValueText)
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle("Charts")
        .background(Color(.systemGroupedBackground))
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("No live samples yet")
                .font(.headline)

            Text("Start live polling from the Live tab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal)
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
