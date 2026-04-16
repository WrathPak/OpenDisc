import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(\.modelContext) private var modelContext
    @State private var voiceSettings = VoiceSettings.load()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ConnectionStatusBar(
                        connectionState: bleManager.connectionState,
                        deviceState: bleManager.deviceState
                    )

                    SpeedDisplay(mph: bleManager.lastThrow?.mph)

                    if let live = bleManager.liveReading {
                        liveGauges(live)
                    }

                    if !bleManager.isCalibrated {
                        calibrationWarning
                    }

                    armButton
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .onAppear {
                bleManager.startLiveStream()
            }
            .onDisappear {
                bleManager.stopLiveStream()
            }
            .onChange(of: bleManager.throwReady) { _, ready in
                if ready {
                    saveThrow()
                    if let response = bleManager.lastThrow {
                        VoiceManager.announceThrow(response, settings: voiceSettings)
                    }
                    bleManager.throwReady = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceSettingsChanged)) { _ in
                voiceSettings = VoiceSettings.load()
            }
        }
    }

    private func liveGauges(_ live: LiveReading) -> some View {
        GlassEffectContainer {
            HStack(spacing: 16) {
                LiveGaugeView(
                    value: live.bestRPM,
                    maxValue: 1000,
                    label: "Spin Rate",
                    unit: "RPM",
                    tint: .blue
                )

                VStack(spacing: 12) {
                    AngleIndicator(angle: live.hyzer, label: "Hyzer")
                    AngleIndicator(angle: live.nose, label: "Nose")
                }
                .padding(12)
                .glassEffect(.regular.tint(.green.opacity(0.15)))
            }
        }
    }

    private var calibrationWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("Calibration required for accurate MPH")
                .font(.subheadline)
        }
        .padding(12)
        .glassEffect(.regular.tint(.orange.opacity(0.2)))
    }

    private var armButton: some View {
        Button {
            HapticManager.armed()
            bleManager.armDevice()
        } label: {
            Label("Arm", systemImage: "scope")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.glass)
        .disabled(bleManager.deviceState != .idle)
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
            isValid: response.valid
        )
        modelContext.insert(throwData)
    }
}
