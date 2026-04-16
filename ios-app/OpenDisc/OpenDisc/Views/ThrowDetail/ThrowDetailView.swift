import SwiftUI

struct ThrowDetailView: View {
    let throwData: ThrowData

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero MPH
                VStack(spacing: 4) {
                    Text(throwData.displayMPH)
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("MPH")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .glassEffect(.regular.tint(.blue.opacity(0.15)))

                // Metrics grid
                LazyVGrid(columns: columns, spacing: 12) {
                    MetricCard(
                        title: "Release RPM",
                        value: String(format: "%.0f", throwData.releaseRPM),
                        unit: "RPM"
                    )
                    MetricCard(
                        title: "Peak RPM",
                        value: String(format: "%.0f", throwData.peakRPM),
                        unit: "RPM"
                    )
                    MetricCard(
                        title: "Hyzer",
                        value: String(format: "%.1f", throwData.launchHyzer),
                        unit: "degrees",
                        tint: .green
                    )
                    MetricCard(
                        title: "Nose Angle",
                        value: String(format: "%.1f", throwData.launchNose),
                        unit: "degrees",
                        tint: .green
                    )
                    MetricCard(
                        title: "Wobble",
                        value: String(format: "%.1f", throwData.wobble),
                        unit: "degrees",
                        tint: wobbleColor
                    )
                    MetricCard(
                        title: "Peak G",
                        value: String(format: "%.1f", throwData.peakG),
                        unit: "g"
                    )
                }

                // Duration
                MetricCard(
                    title: "Duration",
                    value: "\(throwData.durationMS)",
                    unit: "ms"
                )

                // Timestamp
                Text(throwData.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .navigationTitle("Throw Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var wobbleColor: Color {
        if throwData.wobble < 5 { return .green }
        if throwData.wobble < 15 { return .yellow }
        return .orange
    }
}
