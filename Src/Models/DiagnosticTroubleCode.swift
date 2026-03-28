import Foundation

struct DiagnosticTroubleCode: Identifiable, Codable, Equatable {
    let id: UUID
    let code: String

    init(id: UUID = UUID(), code: String) {
        self.id = id
        self.code = code
    }
}
