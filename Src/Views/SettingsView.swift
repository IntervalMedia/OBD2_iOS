import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var obd: OBDService

    var body: some View {
        Form {
            Section {
                LabeledContent("Timeout", value: String(format: "%.1f s", obd.settings.commandTimeoutSeconds))
                    .monospacedDigit()
                Slider(
                    value: Binding(
                        get: { obd.settings.commandTimeoutSeconds },
                        set: { obd.settings.commandTimeoutSeconds = $0 }
                    ),
                    in: 1.0...10.0,
                    step: 0.5
                )
                .accessibilityLabel("Command timeout")
            } header: {
                Text("Adapter response")
            } footer: {
                Text("How long to wait for each adapter command.")
            }

            Section {
                LabeledContent("Interval", value: String(format: "%.1f s", obd.settings.pollingIntervalSeconds))
                    .monospacedDigit()
                Slider(
                    value: Binding(
                        get: { obd.settings.pollingIntervalSeconds },
                        set: { obd.settings.pollingIntervalSeconds = $0 }
                    ),
                    in: 0.5...5.0,
                    step: 0.5
                )
                .accessibilityLabel("Polling interval")
            } header: {
                Text("Live data")
            } footer: {
                Text("Time between live data requests. A longer interval reduces adapter traffic.")
            }

            Section {
                Stepper(
                    value: Binding(
                        get: { obd.settings.maxStoredSamples },
                        set: { obd.settings.maxStoredSamples = $0 }
                    ),
                    in: 100...5000,
                    step: 100
                ) {
                    LabeledContent("Sample limit", value: obd.settings.maxStoredSamples.formatted())
                        .monospacedDigit()
                }
            } header: {
                Text("History")
            } footer: {
                Text("Maximum number of generic OBD samples kept in memory.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .appScreen()
    }
}
