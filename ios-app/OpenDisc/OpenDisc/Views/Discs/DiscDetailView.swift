import SwiftUI
import SwiftData
import Charts

struct DiscDetailView: View {
    @Bindable var disc: Disc
    @State private var showingEdit = false

    private var throws_: [ThrowData] {
        disc.throws_.sorted { $0.timestamp > $1.timestamp }
    }

    private var stats: ThrowStatistics { ThrowStatistics(throws_: throws_) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if throws_.isEmpty {
                    Text("No throws yet with this disc.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 40)
                } else {
                    quickStats
                    if let best = stats.prThrows.first {
                        bestThrowCard(best)
                    }
                    spinSpeedChart
                    recentThrows
                }
            }
            .padding()
        }
        .navigationTitle(disc.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", systemImage: "pencil") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            DiscFormView(disc: disc)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            if !disc.color.isEmpty {
                Text(disc.color)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.15)))
            }
            HStack(spacing: 24) {
                stat("\(throws_.count)", "throws")
                if let last = throws_.first {
                    stat(last.timestamp.formatted(.dateTime.month().day()), "last thrown")
                }
                stat(String(format: "%.0f mm", disc.radius * 1000), "rim")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var quickStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard("Best MPH",
                     stats.bestMPH.map { String(format: "%.1f", $0) } ?? "--",
                     stats.avgMPH.map { String(format: "avg %.1f", $0) } ?? "")
            statCard("Avg RPM",
                     stats.avgRPM.map { String(format: "%.0f", $0) } ?? "--",
                     stats.bestRPM.map { String(format: "best %.0f", $0) } ?? "")
            statCard("Avg Launch",
                     stats.avgLaunch.map { String(format: "%.1f\u{00B0}", $0) } ?? "--",
                     "vertical")
            statCard("Advance",
                     stats.avgAdvanceRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "--",
                     "avg ratio")
        }
    }

    private func statCard(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassEffect(.regular)
    }

    private func bestThrowCard(_ best: ThrowData) -> some View {
        NavigationLink(destination: ThrowDetailView(throwData: best)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personal best")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(best.displayMPH + " mph")
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text(best.timestamp, format: .dateTime.month().day().year())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.title)
                    .foregroundStyle(.yellow)
            }
            .padding(14)
            .glassEffect(.regular.tint(.yellow.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    private var spinSpeedChart: some View {
        let points = throws_.filter { $0.mph > 0 && $0.rpm > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Spin vs Speed")
                .font(.subheadline)
                .fontWeight(.semibold)
            Chart {
                ForEach(points) { t in
                    PointMark(
                        x: .value("MPH", t.mph),
                        y: .value("RPM", t.rpm)
                    )
                    .foregroundStyle(tint(for: t))
                }
            }
            .chartXAxisLabel("MPH")
            .chartYAxisLabel("RPM")
            .frame(height: 180)
            .padding(10)
            .glassEffect(.regular)
        }
    }

    private func tint(for t: ThrowData) -> Color {
        guard let ratio = t.advanceRatio else { return .gray }
        let dev = abs(ratio - t.advanceRatioTarget) / t.advanceRatioTarget
        if dev <= 0.10 { return .green }
        if dev <= 0.20 { return .yellow }
        return .orange
    }

    private var recentThrows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent throws")
                .font(.subheadline)
                .fontWeight(.semibold)
            ForEach(throws_.prefix(10)) { t in
                NavigationLink(destination: ThrowDetailView(throwData: t)) {
                    ThrowRow(throwData: t)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}
