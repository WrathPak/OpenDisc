import SwiftUI

struct ThrowDetailView: View {
    @Bindable var throwData: ThrowData
    @State private var showingEdit = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Disc + tag
                if throwData.disc != nil || throwData.tag != ThrowTag.none.rawValue {
                    HStack(spacing: 12) {
                        if let disc = throwData.disc {
                            Label(disc.displayName, systemImage: "opticaldisc")
                                .font(.subheadline)
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
                        title: "Hyzer",
                        value: String(format: "%.1f", throwData.hyzer),
                        unit: "degrees",
                        tint: .green
                    )
                    MetricCard(
                        title: "Nose Angle",
                        value: String(format: "%.1f", throwData.nose),
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
                        title: "Duration",
                        value: "\(throwData.durationMS)",
                        unit: "ms"
                    )
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
    }

    private var wobbleColor: Color {
        if throwData.wobble < 5 { return .green }
        if throwData.wobble < 15 { return .yellow }
        return .orange
    }
}
