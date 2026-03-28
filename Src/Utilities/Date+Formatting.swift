import Foundation

extension Date {
    func iso8601String() -> String {
        ISO8601DateFormatter().string(from: self)
    }

    func shortTimestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: self)
    }
}
