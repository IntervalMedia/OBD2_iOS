import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var logStore: LogStore

    var body: some View {
        List {
            ForEach(Array(logStore.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    logStore.clear()
                }
            }
        }
    }
}
