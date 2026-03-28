import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var exportURL: URL?
    @Published var lastErrorMessage: String?

    func exportCSV(using service: OBDService) {
        do {
            exportURL = try service.exportCSV()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
