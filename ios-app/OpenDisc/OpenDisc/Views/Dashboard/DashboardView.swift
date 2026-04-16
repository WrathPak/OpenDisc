import SwiftUI

struct DashboardView: View {
    @Environment(BLEManager.self) private var bleManager
    @Binding var selectedDisc: Disc?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ConnectionStatusBar(
                        connectionState: bleManager.connectionState,
                        deviceState: bleManager.deviceState
                    )

                    DiscPicker(selectedDisc: $selectedDisc)

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
}
