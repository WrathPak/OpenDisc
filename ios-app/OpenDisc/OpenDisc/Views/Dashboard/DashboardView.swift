import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(BLEManager.self) private var bleManager
    @Query(sort: \ThrowData.timestamp, order: .reverse) private var throwsDesc: [ThrowData]
    @Binding var selectedDisc: Disc?
    @Binding var throwType: ThrowType
    @Binding var throwHand: ThrowHand
    var storageWarning: String? = nil
    var saveError: String? = nil
    var dumpProgress: Float? = nil
    var dumpSampleCount: Int = 0
    var dumpExpectedCount: Int? = nil
    /// Invoked when the user taps the connection status bar while not
    /// connected. ContentView uses this to open the connect sheet.
    var onTapConnect: (() -> Void)? = nil

    private var recentMPHSeries: [(Int, Float)] {
        throwsDesc.prefix(30)
            .filter { $0.mph > 0 }
            .reversed()
            .enumerated()
            .map { ($0.offset, $0.element.mph) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Button {
                        if bleManager.connectedPeripheral == nil,
                           let onTapConnect {
                            onTapConnect()
                        }
                    } label: {
                        ConnectionStatusBar(
                            connectionState: bleManager.connectionState,
                            deviceState: bleManager.deviceState
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(bleManager.connectedPeripheral != nil)

                    if let storageWarning {
                        errorBanner(title: "Storage",
                                    message: storageWarning,
                                    systemImage: "exclamationmark.octagon.fill",
                                    tint: .red)
                    }
                    if dumpProgress != nil {
                        dumpProgressCard
                    } else if let saveError {
                        errorBanner(title: "Last throw didn't save",
                                    message: saveError,
                                    systemImage: "exclamationmark.triangle.fill",
                                    tint: .orange)
                    }

                    // Throw config selectors
                    HStack(spacing: 12) {
                        DiscPicker(selectedDisc: $selectedDisc)
                        Spacer()
                        ThrowTypePicker(throwType: $throwType, throwHand: $throwHand)
                    }

                    SpeedDisplay(mph: bleManager.lastThrow?.mph)

                    if recentMPHSeries.count >= 3 {
                        sparkline
                    }

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

    private var dumpProgressCard: some View {
        let progress = dumpProgress ?? 0
        let percent = Int(progress * 100)
        let expected = dumpExpectedCount ?? 1920
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading trajectory data")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(percent)%")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(progress))
                .tint(.blue)
            Text("\(dumpSampleCount) / \(expected) samples")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(12)
        .glassEffect(.regular.tint(.blue.opacity(0.18)))
    }

    private func errorBanner(title: String, message: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .glassEffect(.regular.tint(tint.opacity(0.2)))
    }

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MPH trend — last \(recentMPHSeries.count) throws")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(recentMPHSeries, id: \.0) { (i, mph) in
                    LineMark(
                        x: .value("Idx", i),
                        y: .value("MPH", mph)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 48)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular)
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
