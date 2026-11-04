import Foundation

enum ConnectionPhase: Equatable {
    case disconnected
    case connecting
    case adapterConnected
    case initializing(step: Int, total: Int)
    case ready
    case failed(String)
}

/// Validation is separate from transport so a prompt or an error cannot mark a car ready.
enum AdapterSetupResponse {
    static func validate(_ response: String, command: String) throws {
        let values = lines(response, command: command)
        guard !hasFailure(response) else { throw AppError.invalidResponse }
        switch command {
        case "ATZ":
            guard values.contains(where: { $0.hasPrefix("ELM") }) else { throw AppError.invalidResponse }
        case "0100":
            guard !values.isEmpty, values.allSatisfy({
                $0.hasPrefix("4100") && $0.count == 12 && $0.allSatisfy(\.isHexDigit)
            }) else { throw AppError.invalidResponse }
        default:
            guard values == ["OK"] else { throw AppError.invalidResponse }
        }
    }

    static func isDiagnosticResponse(_ response: String, service: String) -> Bool {
        guard !hasFailure(response) else { return false }
        let values = lines(response, command: service == "43" ? "03" : "04")
        guard !values.isEmpty else { return false }
        return values.allSatisfy { value in
            guard value.hasPrefix(service), value.allSatisfy(\.isHexDigit) else { return false }
            if service == "44" { return value == "44" }
            return value.count >= 6 && (value.count - 2) % 4 == 0
        }
    }

    static func lines(_ response: String, command: String) -> [String] {
        response.uppercased().replacingOccurrences(of: "SEARCHING...", with: "")
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == ">" })
            .map { $0.filter { !$0.isWhitespace } }
            .filter { !$0.isEmpty && $0 != command }
    }

    private static func hasFailure(_ response: String) -> Bool {
        let upper = response.uppercased()
        return ["?", "ERROR", "NO DATA", "STOPPED", "UNABLE TO CONNECT", "BUFFER FULL"]
            .contains(where: { upper.contains($0) })
    }
}
