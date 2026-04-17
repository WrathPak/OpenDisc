import SwiftUI
import SwiftData

struct ThrowEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Disc.brand) private var discs: [Disc]

    @Bindable var throwData: ThrowData
    @State private var notes: String = ""
    @State private var selectedTag: ThrowTag = .none
    @State private var selectedType: ThrowType = .backhand
    @State private var selectedHand: ThrowHand = .right
    @State private var showingAddDisc = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Throw Type") {
                    Picker("Hand", selection: $selectedHand) {
                        ForEach(ThrowHand.allCases, id: \.self) { hand in
                            Text(hand == .right ? "Right Hand" : "Left Hand").tag(hand)
                        }
                    }
                    .onChange(of: selectedHand) { oldHand, newHand in
                        if oldHand != newHand {
                            throwData.toggleHand(to: newHand)
                        }
                    }
                    Picker("Type", selection: $selectedType) {
                        ForEach(ThrowType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }

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
                    metricRow("Launch", throwData.displayLaunch)
                    if let ratio = throwData.advanceRatio {
                        metricRow("Advance Ratio", String(format: "%.0f%%", ratio * 100))
                    }
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
                        throwData.throwType = selectedType.rawValue
                        // hand is already updated via toggleHand onChange
                        dismiss()
                    }
                }
            }
            .onAppear {
                notes = throwData.notes
                selectedTag = ThrowTag(rawValue: throwData.tag) ?? .none
                selectedType = ThrowType(rawValue: throwData.throwType) ?? .backhand
                selectedHand = ThrowHand(rawValue: throwData.throwHand) ?? .right
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
