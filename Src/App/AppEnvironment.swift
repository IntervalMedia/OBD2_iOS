import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let logStore: LogStore
    let persistenceStore: PersistenceStore
    let obdService: OBDService

    init() {
        let logStore = LogStore()
        let persistenceStore = PersistenceStore()
        self.logStore = logStore
        self.persistenceStore = persistenceStore
        self.obdService = OBDService(logStore: logStore, persistenceStore: persistenceStore)
    }
}
