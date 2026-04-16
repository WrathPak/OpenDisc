import SwiftUI

struct CalibrationProgressBar: View {
    let progress: CalibrationProgress

    var body: some View {
        VStack(spacing: 16) {
            // Progress bar
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress.progress)
                    .tint(progress.isReady ? .green : .purple)
                    .animation(.smooth, value: progress.progress)

                HStack {
                    Text("\(progress.points) / \(progress.target) points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", progress.progress * 100))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }

            // Current RPM
            HStack {
                Text("Current RPM:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f", progress.rpm))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }

            // RPM range
            HStack(spacing: 4) {
                Text(String(format: "%.0f", progress.rpmMin))
                    .font(.caption2)
                    .monospacedDigit()

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)

                        let minFrac = max(0, (progress.rpmMin - 100) / 600)
                        let maxFrac = min(1, (progress.rpmMax - 100) / 600)
                        Capsule()
                            .fill(Color.purple)
                            .frame(
                                width: geo.size.width * CGFloat(maxFrac - minFrac),
                                height: 6
                            )
                            .offset(x: geo.size.width * CGFloat(minFrac))
                    }
                }
                .frame(height: 6)

                Text(String(format: "%.0f", progress.rpmMax))
                    .font(.caption2)
                    .monospacedDigit()
            }

            // Hint
            Text(progress.hint)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(progress.isReady ? .green : .primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .glassEffect(.regular.tint(progress.isReady ? .green.opacity(0.2) : .purple.opacity(0.15)))
        }
    }
}
