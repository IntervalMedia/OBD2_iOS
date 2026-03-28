import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var obd: OBDService

    var body: some View {
        List {
            Section("Actions") {
                Button("Read Stored DTCs") {
                    Task { await obd.readDTCs() }
                }

                Button("Clear Stored DTCs", role: .destructive) {
                    Task { await obd.clearDTCs() }
                }
            }

            Section("Codes") {
                if obd.dtcs.isEmpty {
                    Text("No codes loaded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(obd.dtcs) { dtc in
                        Text(dtc.code)
                            .font(.body.monospaced())
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
    }
}
