import Foundation

final class AdapterResponseBuffer {
    private var buffer = Data()

    func append(_ data: Data) -> [String] {
        buffer.append(data)

        guard let text = String(data: buffer, encoding: .utf8) else {
            return []
        }

        var responses: [String] = []
        var remaining = text

        while let promptRange = remaining.range(of: ">") {
            let chunk = String(remaining[..<promptRange.lowerBound])
            let cleaned = chunk
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            if !cleaned.isEmpty {
                responses.append(cleaned)
            }

            remaining = String(remaining[promptRange.upperBound...])
        }

        buffer = Data(remaining.utf8)
        return responses
    }

    func clear() {
        buffer.removeAll()
    }
}
