import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(\.modelContext) private var modelContext
    @State private var voiceSettings = VoiceSettings.load()
    @State private var selectedDisc: Disc?
    @State private var throwType: ThrowType = AppSettings.load().defaultThrowType
    @State private var throwHand: ThrowHand = AppSettings.load().defaultThrowHand

    var body: some View {
        TabView {
            DashboardView(
                selectedDisc: $selectedDisc,
                throwType: $throwType,
                throwHand: $throwHand
            )
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
        .onChange(of: bleManager.throwCount) { _, _ in
            saveThrow()
            if let response = bleManager.lastThrow {
                VoiceManager.announceThrow(response, settings: voiceSettings)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceSettingsChanged)) { _ in
            voiceSettings = VoiceSettings.load()
        }
    }

    private var showScan: Binding<Bool> {
        Binding(
            get: { bleManager.connectedPeripheral == nil && bleManager.connectionState != .reconnecting },
            set: { _ in }
        )
    }

    private func saveThrow() {
        guard let response = bleManager.lastThrow, response.valid else { return }
        let throwData = ThrowData(
            timestamp: Date(),
            mph: response.mph,
            rpm: response.rpm,
            peakG: response.peak_g,
            hyzer: response.hyzer,
            nose: response.nose,
            wobble: response.wobble,
            durationMS: response.duration_ms,
            isValid: response.valid,
            disc: selectedDisc,
            throwType: throwType,
            throwHand: throwHand
        )
        modelContext.insert(throwData)
        try? modelContext.save()
    }
}
