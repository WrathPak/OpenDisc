import SwiftUI
import SwiftData

@main
struct OpenDiscApp: App {
    @State private var bleManager = BLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bleManager)
        }
        .modelContainer(for: ThrowData.self)
    }
}
