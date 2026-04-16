import SwiftUI

struct CalibrationView: View {
    @Environment(BLEManager.self) private var bleManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if bleManager.isCalibrating {
                        calibratingView
                    } else if let result = bleManager.calibrationResult {
                        resultView(result)
                    } else if bleManager.isCalibrated {
                        calibratedView
                    } else {
                        uncalibratedView
                    }
                }
                .padding()
            }
            .navigationTitle("Calibrate")
        }
    }

    // MARK: - States

    private var uncalibratedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "gyroscope")
                .font(.system(size: 56))
                .foregroundStyle(.purple)

            Text("Calibration Required")
                .font(.title2)
                .fontWeight(.bold)

            instructionCards

            Button {
                HapticManager.buttonPress()
                bleManager.calibrationResult = nil
                bleManager.startCalibration()
            } label: {
                Label("Start Calibration", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glass)
        }
    }

    private var calibratedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Calibrated")
                .font(.title2)
                .fontWeight(.bold)

            if let status = bleManager.deviceStatus {
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", status.radiusMM))
                            .font(.title)
                            .fontWeight(.bold)
                            .monospacedDigit()
                        Text("Radius (mm)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .glassEffect(.regular.tint(.green.opacity(0.15)))
            }

            Button {
                HapticManager.buttonPress()
                bleManager.calibrationResult = nil
                bleManager.startCalibration()
            } label: {
                Label("Recalibrate", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glass)
        }
    }

    private var calibratingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "gyroscope")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
                .symbolEffect(.rotate, isActive: true)

            Text("Calibrating...")
                .font(.title2)
                .fontWeight(.bold)

            if let progress = bleManager.calibrationProgress {
                CalibrationProgressBar(progress: progress)
                    .padding()
                    .glassEffect(.regular)
            }

            Button {
                HapticManager.buttonPress()
                bleManager.stopCalibration()
            } label: {
                let isReady = bleManager.calibrationProgress?.isReady ?? false
                Label(
                    isReady ? "Save Calibration" : "Stop",
                    systemImage: isReady ? "checkmark" : "stop.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.glass)
        }
    }

    private func resultView(_ result: CalibrationResult) -> some View {
        VStack(spacing: 20) {
            Image(systemName: result.accepted ? "checkmark.circle" : "xmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(result.accepted ? .green : .red)

            Text(result.accepted ? "Calibration Saved" : "Calibration Failed")
                .font(.title2)
                .fontWeight(.bold)

            if result.accepted {
                VStack(spacing: 8) {
                    Text(String(format: "Radius: %.1f mm", result.radiusMM))
                        .font(.headline)
                    Text("\(result.points) points, \(String(format: "%.0f", result.rpmMin))-\(String(format: "%.0f", result.rpmMax)) RPM")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .glassEffect(.regular.tint(.green.opacity(0.15)))
            } else {
                Text(result.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .glassEffect(.regular.tint(.red.opacity(0.15)))
            }

            Button {
                bleManager.calibrationResult = nil
                if !result.accepted {
                    bleManager.startCalibration()
                }
            } label: {
                Text(result.accepted ? "Done" : "Retry")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: - Instructions

    private var instructionCards: some View {
        VStack(spacing: 12) {
            instructionRow(number: 1, text: "Place disc on a lazy susan or turntable")
            instructionRow(number: 2, text: "Tap Start Calibration")
            instructionRow(number: 3, text: "Spin the disc at varying speeds (200-500 RPM)")
            instructionRow(number: 4, text: "When the progress bar fills, tap Save")
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.purple.opacity(0.2)))

            Text(text)
                .font(.subheadline)

            Spacer()
        }
        .padding(12)
        .glassEffect(.regular)
    }
}
