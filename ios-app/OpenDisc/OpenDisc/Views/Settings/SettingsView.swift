import SwiftUI
import AVFoundation
import SwiftData

struct SettingsView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(StorageStatus.self) private var storageStatus
    @Environment(\.modelContext) private var modelContext
    @State private var autoArm: Bool = true
    @State private var triggerG: Float = 3.0
    @State private var wifiEnabled: Bool = true
    @State private var settingsLoaded: Bool = false
    @State private var triggerDebounce: Task<Void, Never>?
    @State private var voice = VoiceSettings.load()
    @State private var appSettings = AppSettings.load()
    @State private var showingResetConfirm = false
    @State private var resetMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Player Defaults") {
                    Picker("Default Hand", selection: $appSettings.defaultThrowHand) {
                        Text("Right Hand").tag(ThrowHand.right)
                        Text("Left Hand").tag(ThrowHand.left)
                    }

                    Picker("Default Throw", selection: $appSettings.defaultThrowType) {
                        Text(ThrowType.backhand.rawValue).tag(ThrowType.backhand)
                        Text(ThrowType.forehand.rawValue).tag(ThrowType.forehand)
                    }

                    NavigationLink("My Discs") {
                        DiscsView()
                    }
                }
                .onChange(of: appSettings) { _, _ in
                    appSettings.save()
                }

                Section("Throw Detection") {
                    Toggle("Auto-Arm", isOn: $autoArm)
                        .onChange(of: autoArm) { _, newValue in
                            guard settingsLoaded else { return }
                            bleManager.updateSettings(autoArm: newValue)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Trigger Threshold")
                            Spacer()
                            Text(String(format: "%.1f g", triggerG))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $triggerG, in: 1.5...8.0, step: 0.5)
                            .onChange(of: triggerG) { _, newValue in
                                guard settingsLoaded else { return }
                                triggerDebounce?.cancel()
                                triggerDebounce = Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else { return }
                                    bleManager.updateSettings(triggerG: newValue)
                                }
                            }
                    }
                }

                Section("Voice Callouts") {
                    Toggle("Enabled", isOn: $voice.enabled)

                    if voice.enabled {
                        Toggle("Speed (MPH)", isOn: $voice.callMPH)
                        Toggle("Spin Rate (RPM)", isOn: $voice.callRPM)
                        Toggle("Hyzer Angle", isOn: $voice.callHyzer)
                        Toggle("Nose Angle", isOn: $voice.callNose)
                        Toggle("Wobble", isOn: $voice.callWobble)
                        Toggle("Peak G-Force", isOn: $voice.callPeakG)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Speech Rate")
                                Spacer()
                                Text(speechRateLabel)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $voice.speechRate, in: 0.3...0.65, step: 0.05)
                        }

                        Button("Test Voice") {
                            let sample = ThrowResponse(
                                type: "throw", valid: true,
                                rpm: 620, mph: 52.3,
                                peak_g: 45.2, hyzer: 12.5,
                                nose: -3.2, wobble: 8.1,
                                duration_ms: 280, release_idx: 0,
                                motion_start_idx: 0, stationary_end: 0,
                                launch: 6.4, seq: nil
                            )
                            VoiceManager.announceThrow(sample, settings: voice)
                        }
                    }
                }
                .onChange(of: voice) { _, newValue in
                    newValue.save()
                    NotificationCenter.default.post(name: .voiceSettingsChanged, object: nil)
                }

                Section("Power") {
                    Toggle("WiFi", isOn: $wifiEnabled)
                        .onChange(of: wifiEnabled) { _, newValue in
                            bleManager.setWifi(enabled: newValue)
                        }

                    Text("Disabling WiFi saves battery (~100 mA)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Device Info") {
                    HStack {
                        Text("Firmware")
                        Spacer()
                        Text(bleManager.firmwareVersion ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Calibration")
                        Spacer()
                        if bleManager.isCalibrated, let status = bleManager.deviceStatus {
                            Text(String(format: "%.1f mm radius", status.radiusMM))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not calibrated")
                                .foregroundStyle(.orange)
                        }
                    }

                    NavigationLink("IMU Diagnostics") {
                        IMUDiagView()
                    }
                }

                Section {
                    Button("Disconnect", role: .destructive) {
                        bleManager.disconnect()
                    }
                }

                Section {
                    Button("Reset local data", role: .destructive) {
                        showingResetConfirm = true
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    if storageStatus.inMemoryFallback, let err = storageStatus.lastError {
                        Text("Store failed to open. Resetting will delete the broken store file so the app can create a fresh one on next launch.\n\n\(err)")
                            .foregroundStyle(.red)
                    } else {
                        Text("Deletes all saved throws and discs on this device. Use only if storage is broken or you want a clean slate.")
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all throws and discs?",
                                isPresented: $showingResetConfirm,
                                titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { resetLocalData() }
            } message: {
                Text("This can't be undone. The app will need to be re-launched.")
            }
            .alert("Reset", isPresented: .constant(resetMessage != nil), actions: {
                Button("OK") { resetMessage = nil }
            }, message: {
                Text(resetMessage ?? "")
            })
            .onAppear {
                bleManager.getSettings()
            }
            .onChange(of: bleManager.deviceSettings) { _, settings in
                guard let settings else { return }
                autoArm = settings.autoArm
                triggerG = settings.triggerG
                settingsLoaded = true
            }
        }
    }

    /// Wipes the persistent store files. If the container is healthy we also
    /// delete all model rows first; if it failed to open, we just remove the
    /// store files. Either way, the next app launch creates a fresh store.
    private func resetLocalData() {
        resetMessage = nil
        if !storageStatus.inMemoryFallback {
            do {
                try modelContext.delete(model: ThrowData.self)
                try modelContext.delete(model: Disc.self)
                try modelContext.save()
            } catch {
                resetMessage = "Row delete failed: \(error)\n\nAttempting file-level wipe anyway."
            }
        }
        if let url = storageStatus.storeURL {
            let fm = FileManager.default
            let siblings = [url,
                            url.appendingPathExtension("shm"),
                            url.appendingPathExtension("wal")]
            for p in siblings { try? fm.removeItem(at: p) }
        }
        resetMessage = (resetMessage ?? "") + "Local data cleared. Quit the app from the App Switcher and re-open to start fresh."
    }

    private var speechRateLabel: String {
        if voice.speechRate < 0.4 { return "Slow" }
        if voice.speechRate < 0.55 { return "Normal" }
        return "Fast"
    }
}
