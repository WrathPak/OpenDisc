import SwiftUI
import SwiftData
import OSLog

private let appLog = Logger(subsystem: "com.opendisc.app", category: "storage")

/// Flipped to true when the persistent ModelContainer fails to open and we
/// fall back to in-memory. Read from the UI to surface a warning banner.
@Observable
final class StorageStatus {
    var inMemoryFallback: Bool = false
    var lastError: String? = nil

    /// Absolute path to the on-disk store — surfaced so Settings can offer a
    /// "Reset local data" action that wipes it.
    var storeURL: URL? = nil
}

@main
struct OpenDiscApp: App {
    @State private var bleManager = BLEManager()
    @State private var storageStatus = StorageStatus()
    private let container: ModelContainer

    init() {
        let schema = Schema(versionedSchema: SchemaV3.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let status = StorageStatus()
        status.storeURL = config.url

        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: OpenDiscMigrationPlan.self,
                configurations: [config]
            )
            appLog.info("ModelContainer opened at \(config.url.path, privacy: .public)")
        } catch {
            let msg = "\(error)"
            appLog.error("ModelContainer init FAILED: \(msg, privacy: .public). Running in-memory — writes won't persist.")
            status.inMemoryFallback = true
            status.lastError = msg
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [memoryConfig])
        }
        _storageStatus = State(initialValue: status)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bleManager)
                .environment(storageStatus)
        }
        .modelContainer(container)
    }
}
