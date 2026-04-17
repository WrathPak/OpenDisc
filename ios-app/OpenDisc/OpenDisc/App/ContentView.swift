import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(StorageStatus.self) private var storageStatus
    @Environment(\.modelContext) private var modelContext
    @State private var voiceSettings = VoiceSettings.load()
    @State private var selectedDisc: Disc?
    @State private var throwType: ThrowType = AppSettings.load().defaultThrowType
    @State private var throwHand: ThrowHand = AppSettings.load().defaultThrowHand

    /// The most recently saved throw, pending its raw-dump payload.
    @State private var pendingThrow: ThrowData?

    /// Most recent throw-save error, cleared on the next successful save.
    @State private var lastSaveError: String?

    var body: some View {
        TabView {
            DashboardView(
                selectedDisc: $selectedDisc,
                throwType: $throwType,
                throwHand: $throwHand,
                storageWarning: storageWarning,
                saveError: lastSaveError,
                dumpProgress: bleManager.isDumping ? bleManager.dumpProgress : nil,
                dumpSampleCount: bleManager.dumpSamples.count,
                dumpExpectedCount: bleManager.dumpExpectedCount
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
        .onChange(of: bleManager.isDumping) { wasDumping, nowDumping in
            // Dump finished. If dumpComplete never flipped true (e.g. firmware
            // returned `no_throw`), persistRawDump still runs so we can log it
            // and clear pendingThrow instead of silently stranding it.
            if wasDumping && !nowDumping && !bleManager.dumpComplete {
                print("[dump] ended without a `done` status — firmware may have returned no_throw")
                persistRawDump()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceSettingsChanged)) { _ in
            voiceSettings = VoiceSettings.load()
        }
    }

    private var storageWarning: String? {
        if storageStatus.inMemoryFallback {
            return "Storage error — running in-memory. Writes won't persist. " + (storageStatus.lastError ?? "")
        }
        return nil
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
        do {
            try modelContext.save()
            lastSaveError = nil
            print("[saveThrow] inserted + saved mph=\(response.mph) valid=\(response.valid)")
        } catch {
            lastSaveError = "\(error)"
            print("[saveThrow] SAVE FAILED: \(error)")
        }

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
        guard let throwData = pendingThrow else {
            print("[persistRawDump] no pendingThrow — skipping")
            return
        }
        let samples = bleManager.dumpSamples
        let failures = bleManager.dumpDecodeFailures
        let firstError = bleManager.dumpDecodeLastError ?? "(no decode error recorded)"
        let status = bleManager.dumpLastStatus ?? "(never received)"
        let expected = bleManager.dumpExpectedCount.map(String.init) ?? "?"
        print("[persistRawDump] dump complete — samples=\(samples.count) decodeFailures=\(failures) status=\(status) expected=\(expected)")
        guard !samples.isEmpty else {
            if failures > 0 {
                lastSaveError = "Trajectory dump: \(failures) samples failed to decode, 0 stored. Firmware status=\(status). First error: \(firstError)"
            } else {
                lastSaveError = "Trajectory dump — firmware status=\(status), expected=\(expected), received=0. 3D view unavailable for this throw."
            }
            pendingThrow = nil
            return
        }
        // Sort by sample index so later consumers (TrajectoryEngine) get
        // chronological order even if frames arrived out of order.
        let sorted = samples.sorted { $0.i < $1.i }
        do {
            let encoded = try JSONEncoder().encode(sorted)
            throwData.rawSamples = encoded
            try modelContext.save()
            print("[persistRawDump] saved \(encoded.count) bytes (\(sorted.count) samples)")
            let expected = bleManager.dumpExpectedCount ?? 0
            if expected > 0 && sorted.count < expected {
                let pct = Int(Float(sorted.count) / Float(expected) * 100)
                let calls = bleManager.dumpFrameCallCount
                let dedup = bleManager.dumpFrameDedupCount
                let hdrReject = bleManager.dumpFrameHeaderRejectCount
                let unique = bleManager.dumpReceivedFrames.count
                lastSaveError = "Trajectory partial: \(sorted.count)/\(expected) samples (\(pct)%). callbacks=\(calls) headerReject=\(hdrReject) dup=\(dedup) uniqueSeqs=\(unique). Some BLE frames were dropped."
            } else {
                lastSaveError = nil
            }
        } catch {
            lastSaveError = "Raw dump save failed: \(error)"
            print("[persistRawDump] SAVE FAILED: \(error)")
        }
        pendingThrow = nil
    }
}
