import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var obd: OBDService

    var body: some View {
        Form {
            Section("Command Timeout") {
                HStack {
                    Text("Timeout")
                    Spacer()
                    Text(String(format: "%.1f s", obd.settings.commandTimeoutSeconds))
                }

                Slider(
                    value: Binding(
                        get: { obd.settings.commandTimeoutSeconds },
                        set: { obd.settings.commandTimeoutSeconds = $0 }
                    ),
                    in: 1.0...10.0,
                    step: 0.5
                )
            }

            Section("Polling Interval") {
                HStack {
                    Text("Interval")
                    Spacer()
                    Text(String(format: "%.1f s", obd.settings.pollingIntervalSeconds))
                }

                Slider(
                    value: Binding(
                        get: { obd.settings.pollingIntervalSeconds },
                        set: { obd.settings.pollingIntervalSeconds = $0 }
                    ),
                    in: 0.5...5.0,
                    step: 0.5
                )
            }

            Section("Stored Samples") {
                Stepper(
                    value: Binding(
                        get: { obd.settings.maxStoredSamples },
                        set: { obd.settings.maxStoredSamples = $0 }
                    ),
                    in: 100...5000,
                    step: 100
                ) {
                    HStack {
                        Text("Max samples")
                        Spacer()
                        Text("\(obd.settings.maxStoredSamples)")
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}
