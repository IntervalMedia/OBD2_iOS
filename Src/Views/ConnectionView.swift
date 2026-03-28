import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var obd: OBDService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                connectionCard
                actionCard
            }
            .padding()
        }
        .navigationTitle("Connection")
        .background(Color(.systemGroupedBackground))
    }

    private var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                labelValue("State", obd.connectionStateDescription)
                labelValue("Initialized", obd.isInitialized ? "Yes" : "No")
                labelValue("VIN", obd.vehicleInfo.vin ?? "Unavailable")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Adapter Status", systemImage: "dot.radiowaves.left.and.right")
        }
    }

    private var connectionCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                TextField("Host", text: Binding(
                    get: { obd.settings.host },
                    set: { obd.settings.host = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                TextField("Port", value: Binding(
                    get: { Int(obd.settings.port) },
                    set: { obd.settings.port = UInt16($0 ?? 35000) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
            }
        } label: {
            Label("Network", systemImage: "network")
        }
    }

    private var actionCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                Button("Connect") { obd.connect() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                Button("Initialize Adapter") {
                    Task { await obd.initializeAdapter() }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Read VIN") {
                    Task { await obd.readVIN() }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Disconnect", role: .destructive) {
                    obd.disconnect()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        } label: {
            Label("Actions", systemImage: "bolt.horizontal.circle")
        }
    }

    private func labelValue(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}
