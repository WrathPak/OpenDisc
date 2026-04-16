import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(BLEManager.self) private var bleManager
    @State private var autoArm: Bool = true
    @State private var triggerG: Float = 3.0
    @State private var wifiEnabled: Bool = true
    @State private var settingsLoaded: Bool = false
    @State private var triggerDebounce: Task<Void, Never>?
    @State private var voice = VoiceSettings.load()
    @State private var appSettings = AppSettings.load()

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    Picker("Throwing Hand", selection: $appSettings.handedness) {
                        ForEach(Handedness.allCases, id: \.self) { h in
                            Text(h.rawValue).tag(h)
                        }
                    }
                    .onChange(of: appSettings.handedness) { _, _ in
                        appSettings.save()
                    }

                    NavigationLink("My Discs") {
                        DiscsView()
                    }
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
                                motion_start_idx: 0, stationary_end: 0
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
            }
            .navigationTitle("Settings")
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

    private var speechRateLabel: String {
        if voice.speechRate < 0.4 { return "Slow" }
        if voice.speechRate < 0.55 { return "Normal" }
        return "Fast"
    }
}
