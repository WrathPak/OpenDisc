import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(\.modelContext) private var modelContext
    @State private var voiceSettings = VoiceSettings.load()
    @State private var selectedDisc: Disc?
    @State private var throwType: ThrowType = AppSettings.load().defaultThrowType
    @State private var throwHand: ThrowHand = AppSettings.load().defaultThrowHand

    /// The most recently saved throw, pending its raw-dump payload.
    @State private var pendingThrow: ThrowData?

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

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.xaxis")
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
        .onChange(of: bleManager.dumpComplete) { _, complete in
            if complete { persistRawDump() }
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
        guard let response = bleManager.lastThrow else { return }
        let status = bleManager.deviceStatus
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
        throwData.releaseIdx = response.release_idx
        throwData.calRx = status?.calRX ?? 0
        throwData.calRy = status?.calRY ?? 0
        throwData.launchAngle = response.launch ?? 0
        modelContext.insert(throwData)
        try? modelContext.save()

        // PR check against all persisted throws.
        let allThrows = (try? modelContext.fetch(FetchDescriptor<ThrowData>())) ?? []
        if let message = PRService.checkForPR(candidate: throwData, history: allThrows) {
            HapticManager.armed()
            VoiceManager.announcePR(message, settings: voiceSettings)
        }

        // Kick off the raw dump so we can reconstruct the trajectory later.
        pendingThrow = throwData
        bleManager.dumpRaw()
    }

    private func persistRawDump() {
        guard let throwData = pendingThrow else { return }
        let samples = bleManager.dumpSamples
        guard !samples.isEmpty else {
            pendingThrow = nil
            return
        }
        if let encoded = try? JSONEncoder().encode(samples) {
            throwData.rawSamples = encoded
            try? modelContext.save()
        }
        pendingThrow = nil
    }
}
