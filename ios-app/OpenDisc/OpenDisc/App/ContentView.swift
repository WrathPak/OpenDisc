import SwiftUI

struct ContentView: View {
    @Environment(BLEManager.self) private var bleManager

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.open.with.lines.needle.33percent")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "list.bullet.clipboard")
                }

            CalibrationView()
                .tabItem {
                    Label("Calibrate", systemImage: "scope")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .fullScreenCover(isPresented: showScan) {
            ScanView()
        }
    }

    private var showScan: Binding<Bool> {
        Binding(
            get: { bleManager.connectedPeripheral == nil && bleManager.connectionState != .reconnecting },
            set: { _ in }
        )
    }
}
