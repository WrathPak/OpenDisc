import SwiftUI

struct SettingsView: View {
    @Environment(BLEManager.self) private var bleManager
    @State private var autoArm: Bool = true
    @State private var triggerG: Float = 3.0
    @State private var wifiEnabled: Bool = true
    @State private var settingsLoaded: Bool = false
    @State private var triggerDebounce: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
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
}
