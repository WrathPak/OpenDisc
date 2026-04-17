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

    /// Set when the user taps the status bar to open the connect sheet.
    @State private var showingConnectSheet = false

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
                dumpExpectedCount: bleManager.dumpExpectedCount,
                onTapConnect: { showingConnectSheet = true }
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
        .sheet(isPresented: $showingConnectSheet) {
            ScanView(onConnected: { showingConnectSheet = false })
        }
        .onAppear {
            // Kick off a background scan on launch so a nearby OpenDisc
            // auto-connects without forcing the user to open the sheet.
            if bleManager.connectedPeripheral == nil
                && bleManager.connectionState != .reconnecting {
                bleManager.startScanning()
            }
        }
        .onChange(of: bleManager.throwCount) { _, _ in
            let isNew = saveThrow()
            if isNew, let response = bleManager.lastThrow {
                VoiceManager.announceThrow(response, settings: voiceSettings)
            }
        }
        .onChange(of: bleManager.deviceStatus?.throwSeq) { _, newSeq in
            // Auto-pull: firmware's seq is ahead of our local max, meaning a
            // throw completed while we were out of BT range. Fetch it now.
            // Firmware < 1.0.1 has nil throwSeq — we can't tell, so skip.
            guard let newSeq, newSeq > 0 else { return }
            let localMax = (try? modelContext.fetch(FetchDescriptor<ThrowData>()))?
                .map(\.throwSeq).max() ?? -1
            if newSeq > localMax {
                print("[auto-pull] firmware seq=\(newSeq) > local max=\(localMax) — fetching last throw")
                bleManager.fetchThrow()
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


    /// Ingests `bleManager.lastThrow` into the SwiftData store.
    /// Returns `true` if a new row was inserted, `false` if this was a duplicate
    /// of an already-saved throw (matched by firmware-supplied seq).
    @discardableResult
    private func saveThrow() -> Bool {
        guard let response = bleManager.lastThrow else { return false }
        let status = bleManager.deviceStatus

        // Dedupe: if the firmware gave us a seq and we already have a throw
        // with that seq, don't create a duplicate. Re-trigger dumpRaw anyway
        // so a prior dump failure can still be recovered.
        if let seq = response.seq, seq >= 0 {
            let match = (try? modelContext.fetch(
                FetchDescriptor<ThrowData>(
                    predicate: #Predicate { $0.throwSeq == seq }
                )
            ))?.first
            if let existing = match {
                print("[saveThrow] dedupe hit on seq=\(seq) — skipping insert, refetching raw")
                pendingThrow = existing
                bleManager.dumpRaw()
                return false
            }
        }

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
        throwData.throwSeq = response.seq ?? -1
        modelContext.insert(throwData)
        do {
            try modelContext.save()
            lastSaveError = nil
            print("[saveThrow] inserted seq=\(throwData.throwSeq) mph=\(response.mph) valid=\(response.valid)")
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
        return true
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
