import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var logStore: LogStore

    var body: some View {
        Group {
            if logStore.lines.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "text.alignleft",
                    description: Text("Adapter commands and connection activity will appear here.")
                )
            } else {
                List {
                    Section {
                        ForEach(Array(logStore.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        }
                    } header: {
                        Text("\(logStore.lines.count) entries")
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Activity")
        .appScreen()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear log", systemImage: "trash") {
                    logStore.clear()
                }
                .disabled(logStore.lines.isEmpty)
            }
        }
    }
}
