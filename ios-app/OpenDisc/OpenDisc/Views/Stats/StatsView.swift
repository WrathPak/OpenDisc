import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \ThrowData.timestamp, order: .reverse) private var allThrows: [ThrowData]
    @Query(sort: \Disc.brand) private var discs: [Disc]

    @AppStorage("stats.dateRange") private var dateRangeRaw: String = StatsDateRange.week.rawValue
    @AppStorage("stats.typeFilter") private var typeRaw: String = StatsTypeFilter.all.rawValue
    @AppStorage("stats.handFilter") private var handRaw: String = StatsHandFilter.all.rawValue
    @AppStorage("stats.discIDString") private var discIDString: String = ""

    @State private var filter = StatsFilter()

    private var filtered: [ThrowData] { filter.apply(to: allThrows) }
    private var stats: ThrowStatistics { ThrowStatistics(throws_: filtered) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    filterBar
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        aggregateCards
                        chartsSection
                        prSection
                    }
                }
                .padding()
            }
            .navigationTitle("Stats")
        }
        .onAppear { loadFilter() }
        .onChange(of: filter.dateRange) { _, v in dateRangeRaw = v.rawValue }
        .onChange(of: filter.typeFilter) { _, v in typeRaw = v.rawValue }
        .onChange(of: filter.handFilter) { _, v in handRaw = v.rawValue }
        .onChange(of: filter.discID) { _, v in
            discIDString = v.map { "\($0.hashValue)" } ?? ""
        }
    }

    private func loadFilter() {
        filter.dateRange = StatsDateRange(rawValue: dateRangeRaw) ?? .week
        filter.typeFilter = StatsTypeFilter(rawValue: typeRaw) ?? .all
        filter.handFilter = StatsHandFilter(rawValue: handRaw) ?? .all
        // discID persistence by hash is lossy; just match by hash if found
        if let matched = discs.first(where: { "\($0.persistentModelID.hashValue)" == discIDString }) {
            filter.discID = matched.persistentModelID
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("Range", selection: $filter.dateRange) {
                ForEach(StatsDateRange.allCases) { r in Text(r.rawValue).tag(r) }
            }
            .pickerStyle(.segmented)

            HStack {
                Picker("Type", selection: $filter.typeFilter) {
                    ForEach(StatsTypeFilter.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)

                Picker("Hand", selection: $filter.handFilter) {
                    ForEach(StatsHandFilter.allCases) { h in Text(h.rawValue).tag(h) }
                }
                .pickerStyle(.segmented)
            }

            if !discs.isEmpty {
                Menu {
                    Button("All discs") { filter.discID = nil }
                    ForEach(discs) { disc in
                        Button(disc.displayName) { filter.discID = disc.persistentModelID }
                    }
                } label: {
                    HStack {
                        Image(systemName: "opticaldisc")
                        Text(selectedDiscName)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular)
                }
            }
        }
    }

    private var selectedDiscName: String {
        guard let discID = filter.discID,
              let disc = discs.first(where: { $0.persistentModelID == discID }) else {
            return "All discs"
        }
        return disc.displayName
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No throws match these filters")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Aggregate cards

    private var aggregateCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard("Throws", "\(stats.count)", "total")
            statCard("Best MPH",
                     stats.bestMPH.map { String(format: "%.1f", $0) } ?? "--",
                     stats.avgMPH.map { String(format: "avg %.1f", $0) } ?? "")
            statCard("Best RPM",
                     stats.bestRPM.map { String(format: "%.0f", $0) } ?? "--",
                     stats.avgRPM.map { String(format: "avg %.0f", $0) } ?? "")
            statCard("Avg Launch",
                     stats.avgLaunch.map { String(format: "%.1f\u{00B0}", $0) } ?? "--",
                     "vertical angle")
            statCard("Avg Hyzer",
                     stats.avgHyzer.map { String(format: "%.1f\u{00B0}", $0) } ?? "--",
                     stats.avgNose.map { String(format: "nose %.1f\u{00B0}", $0) } ?? "")
            statCard("Advance",
                     stats.avgAdvanceRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "--",
                     "avg ratio")
            if let score = stats.consistencyScore {
                statCard("Consistency", "\(score)", "out of 100")
            }
            statCard("Avg Wobble",
                     stats.avgWobble.map { String(format: "%.1f\u{00B0}", $0) } ?? "--",
                     "lower is cleaner")
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

    // MARK: - Charts

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartHeader("MPH over time")
            mphChart

            chartHeader("Spin vs Speed")
            spinSpeedChart

            chartHeader("Hyzer distribution")
            histogramChart(values: filtered.map(\.hyzer),
                           buckets: 8, unit: "\u{00B0}")

            chartHeader("Wobble distribution")
            histogramChart(values: filtered.map(\.wobble),
                           buckets: 8, unit: "\u{00B0}")
        }
    }

    private func chartHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private var mphChart: some View {
        let valid = filtered.filter { $0.mph > 0 }.sorted { $0.timestamp < $1.timestamp }
        let rolling = rollingAverage(valid.map(\.mph), window: 5)
        return Chart {
            ForEach(Array(valid.enumerated()), id: \.offset) { (i, t) in
                PointMark(
                    x: .value("Time", t.timestamp),
                    y: .value("MPH", t.mph)
                )
                .foregroundStyle(.blue.opacity(0.5))
            }
            ForEach(Array(valid.enumerated()), id: \.offset) { (i, t) in
                LineMark(
                    x: .value("Time", t.timestamp),
                    y: .value("Rolling", rolling[i])
                )
                .foregroundStyle(.orange)
                .interpolationMethod(.catmullRom)
            }
        }
        .frame(height: 160)
        .padding(10)
        .glassEffect(.regular)
    }

    private func rollingAverage(_ values: [Float], window: Int) -> [Float] {
        guard !values.isEmpty else { return [] }
        return values.indices.map { i in
            let start = max(0, i - window + 1)
            let slice = values[start...i]
            return slice.reduce(0, +) / Float(slice.count)
        }
    }

    private var spinSpeedChart: some View {
        let points = filtered.filter { $0.mph > 0 && $0.rpm > 0 }
        return Chart {
            ForEach(points) { t in
                PointMark(
                    x: .value("MPH", t.mph),
                    y: .value("RPM", t.rpm)
                )
                .foregroundStyle(advanceTint(for: t))
            }
        }
        .chartXAxisLabel("MPH")
        .chartYAxisLabel("RPM")
        .frame(height: 160)
        .padding(10)
        .glassEffect(.regular)
    }

    private func advanceTint(for t: ThrowData) -> Color {
        guard let ratio = t.advanceRatio else { return .gray }
        let dev = abs(ratio - t.advanceRatioTarget) / t.advanceRatioTarget
        if dev <= 0.10 { return .green }
        if dev <= 0.20 { return .yellow }
        return .orange
    }

    private func histogramChart(values: [Float], buckets: Int, unit: String) -> some View {
        let bins = buildHistogram(values: values, buckets: buckets)
        return Chart {
            ForEach(bins, id: \.lowerBound) { bin in
                BarMark(
                    x: .value("Bin", String(format: "%.0f", bin.lowerBound)),
                    y: .value("Count", bin.count)
                )
                .foregroundStyle(.blue.opacity(0.6))
            }
        }
        .frame(height: 140)
        .padding(10)
        .glassEffect(.regular)
    }

    private func buildHistogram(values: [Float], buckets: Int) -> [HistogramBin] {
        guard values.count > 1, let lo = values.min(), let hi = values.max(), hi > lo else {
            return []
        }
        let step = (hi - lo) / Float(buckets)
        var bins: [HistogramBin] = (0..<buckets).map {
            HistogramBin(lowerBound: lo + Float($0) * step,
                         upperBound: lo + Float($0 + 1) * step,
                         count: 0)
        }
        for v in values {
            var idx = Int((v - lo) / step)
            if idx >= buckets { idx = buckets - 1 }
            if idx < 0 { idx = 0 }
            bins[idx].count += 1
        }
        return bins
    }

    // MARK: - PR section

    private var prSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top throws")
                .font(.subheadline)
                .fontWeight(.semibold)
            ForEach(stats.prThrows) { pr in
                NavigationLink(destination: ThrowDetailView(throwData: pr)) {
                    HStack {
                        Text(pr.displayMPH + " mph")
                            .font(.headline)
                            .monospacedDigit()
                        Spacer()
                        Text(pr.timestamp, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular.tint(.yellow.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HistogramBin {
    let lowerBound: Float
    let upperBound: Float
    var count: Int
}
