import SwiftUI
import SwiftData

struct ThrowEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Disc.brand) private var discs: [Disc]

    @Bindable var throwData: ThrowData
    @State private var notes: String = ""
    @State private var selectedTag: ThrowTag = .none
    @State private var showingAddDisc = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Disc") {
                    Picker("Disc", selection: $throwData.disc) {
                        Text("None").tag(nil as Disc?)
                        ForEach(discs) { disc in
                            Text(disc.displayName).tag(disc as Disc?)
                        }
                    }

                    Button("Add New Disc...") {
                        showingAddDisc = true
                    }
                }

                Section("Tag") {
                    Picker("Tag", selection: $selectedTag) {
                        ForEach(ThrowTag.allCases, id: \.self) { tag in
                            Text(tag.rawValue).tag(tag)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Notes") {
                    TextField("Add notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Metrics") {
                    metricRow("MPH", throwData.displayMPH)
                    metricRow("RPM", throwData.displayRPM)
                    metricRow("Hyzer", throwData.displayHyzer)
                    metricRow("Nose", String(format: "%.1f\u{00B0}", throwData.nose))
                    metricRow("Wobble", String(format: "%.1f\u{00B0}", throwData.wobble))
                    metricRow("Peak G", String(format: "%.1f g", throwData.peakG))
                }
            }
            .navigationTitle("Edit Throw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        throwData.notes = notes
                        throwData.tag = selectedTag.rawValue
                        dismiss()
                    }
                }
            }
            .onAppear {
                notes = throwData.notes
                selectedTag = ThrowTag(rawValue: throwData.tag) ?? .none
            }
            .sheet(isPresented: $showingAddDisc) {
                DiscFormView()
            }
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }
}
