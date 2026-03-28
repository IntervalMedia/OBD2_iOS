import Foundation

@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var lines: [String] = []

    func append(_ message: String) {
        lines.append("[\(Date().shortTimestampString())] \(message)")
        if lines.count > 1000 {
            lines.removeFirst(lines.count - 1000)
        }
    }

    func clear() {
        lines.removeAll()
    }
}
