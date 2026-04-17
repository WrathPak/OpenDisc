import SwiftUI
import Charts

struct ThrowDetailView: View {
    @Bindable var throwData: ThrowData
    @State private var showingEdit = false
    @State private var showingTrajectory = false
    @State private var trajectory: Trajectory?
    @State private var trajectoryError: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Throw info badges
                HStack(spacing: 8) {
                    Text(throwData.displayThrowType)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular.tint(.orange.opacity(0.2)))

                    if let disc = throwData.disc {
                        Label(disc.displayName, systemImage: "opticaldisc")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.tint(.accentColor.opacity(0.2)))
                    }

                    if throwData.tag != ThrowTag.none.rawValue {
                        Text(throwData.tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.tint(.purple.opacity(0.2)))
                    }
                }

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
                        title: "RPM",
                        value: String(format: "%.0f", throwData.rpm),
                        unit: "RPM"
                    )
                    MetricCard(
                        title: "Peak G",
                        value: String(format: "%.1f", throwData.peakG),
                        unit: "g"
                    )
                    MetricCard(
                        title: throwData.hyzer >= 0 ? "Hyzer" : "Anhyzer",
                        value: String(format: "%.1f", abs(throwData.hyzer)),
                        unit: "degrees",
                        tint: .green
                    )
                    MetricCard(
                        title: "Nose Angle",
                        value: String(format: "%.1f", throwData.nose),
                        unit: "degrees",
                        tint: .green
                    )
                    launchCard
                    advanceRatioCard
                    MetricCard(
                        title: "Wobble",
                        value: String(format: "%.1f", throwData.wobble),
                        unit: "degrees",
                        tint: wobbleColor
                    )
                    MetricCard(
                        title: "Duration",
                        value: "\(throwData.durationMS)",
                        unit: "ms"
                    )
                    carryCard
                }

                if throwData.predictedCarryFeet != nil {
                    flightPathChart
                }

                // 3D trajectory
                if throwData.hasTrajectoryData {
                    Button {
                        computeAndShowTrajectory()
                    } label: {
                        Label("View 3D Trajectory", systemImage: "scope")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.slash")
                            .foregroundStyle(.secondary)
                        Text("3D trajectory unavailable — raw sample dump wasn't captured for this throw.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular)
                }

                Text(String(format: "Raw samples stored: %d bytes", throwData.rawSamples?.count ?? 0))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if let msg = trajectoryError {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Notes
                if !throwData.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(throwData.notes)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassEffect(.regular)
                }

                // Timestamp
                Text(throwData.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .navigationTitle("Throw Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", systemImage: "pencil") {
                    showingEdit = true
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            ThrowEditView(throwData: throwData)
        }
        .sheet(isPresented: $showingTrajectory) {
            if let trajectory {
                TrajectoryView(trajectory: trajectory)
            }
        }
    }

    private var launchCard: some View {
        let available = throwData.mph >= 0
        let title = "Launch"
        let value: String
        let unit: String
        if !available {
            value = "--"
            unit = "unavailable"
        } else if abs(throwData.launchAngle) < 0.5 {
            value = "0"
            unit = "flat"
        } else {
            value = String(format: "%.1f", abs(throwData.launchAngle))
            unit = throwData.launchAngle >= 0 ? "deg up" : "deg down"
        }
        return MetricCard(title: title, value: value, unit: unit, tint: .green)
    }

    private var advanceRatioCard: some View {
        let ratio = throwData.advanceRatio
        let target = throwData.advanceRatioTarget
        let value: String
        let unit: String
        let tint: Color
        if let ratio {
            value = String(format: "%.0f%%", ratio * 100)
            unit = String(format: "target %.0f%%", target * 100)
            let deviation = abs(ratio - target) / target
            if deviation <= 0.10 { tint = .green }
            else if deviation <= 0.20 { tint = .yellow }
            else { tint = .orange }
        } else {
            value = "--"
            unit = "advance ratio"
            tint = .gray
        }
        return MetricCard(title: "Advance Ratio", value: value, unit: unit, tint: tint)
    }

    private var carryCard: some View {
        let value: String
        let unit: String
        if let feet = throwData.predictedCarryFeet {
            value = String(format: "%.0f", feet)
            unit = "ft predicted"
        } else {
            value = "--"
            unit = "carry"
        }
        return MetricCard(title: "Carry", value: value, unit: unit, tint: .cyan)
    }

    @ViewBuilder
    private var flightPathChart: some View {
        if let result = FlightSimulator.predict(
            mph: throwData.mph,
            launchAngleDeg: throwData.launchAngle,
            hyzerDeg: throwData.hyzer
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Predicted flight (side view)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(Array(result.path.enumerated()), id: \.offset) { (_, p) in
                        LineMark(
                            x: .value("Distance", p.x * 3.28084),
                            y: .value("Height", p.z * 3.28084)
                        )
                        .foregroundStyle(.cyan)
                    }
                }
                .chartXAxisLabel("ft")
                .chartYAxisLabel("ft")
                .frame(height: 140)
                .padding(10)
                .glassEffect(.regular)
                Text(String(format: "Carry %.0f ft · Apex %.0f ft", result.carryFeet, result.apexFeet))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var wobbleColor: Color {
        if throwData.wobble < 5 { return .green }
        if throwData.wobble < 15 { return .yellow }
        return .orange
    }

    private func computeAndShowTrajectory() {
        trajectoryError = nil
        guard let samples = throwData.decodedSamples, !samples.isEmpty else {
            trajectoryError = "No raw sample data available for this throw."
            return
        }
        let releaseIdx = throwData.releaseIdx < samples.count ? throwData.releaseIdx : nil
        guard let result = TrajectoryEngine.compute(
            samples: samples,
            releaseIndex: releaseIdx,
            calRx: throwData.calRx,
            calRy: throwData.calRy
        ) else {
            trajectoryError = "Couldn't reconstruct trajectory — burst too short or no stationary reference."
            return
        }
        trajectory = result
        showingTrajectory = true
    }
}
