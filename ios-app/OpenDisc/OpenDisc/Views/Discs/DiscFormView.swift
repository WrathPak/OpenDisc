import SwiftUI
import SwiftData

struct DiscFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var disc: Disc?

    @State private var brand: String = ""
    @State private var model: String = ""
    @State private var color: String = ""
    @State private var notes: String = ""
    @State private var radiusMM: Double = 105
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Disc Info") {
                    TextField("Brand", text: $brand)
                    TextField("Model", text: $model)
                    TextField("Color (optional)", text: $color)
                }

                Section {
                    HStack {
                        Text("Radius")
                        Spacer()
                        TextField("105", value: $radiusMM, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                        Text("mm")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Rim Radius")
                } footer: {
                    Text("Used for advance-ratio calculation. Default 105 mm fits most drivers.")
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(disc == nil ? "New Disc" : "Edit Disc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(brand.isEmpty || model.isEmpty)
                }
            }
            .onAppear {
                if let disc {
                    brand = disc.brand
                    model = disc.model
                    color = disc.color
                    notes = disc.notes
                    radiusMM = Double(disc.radius * 1000)
                }
            }
            .alert("Save failed", isPresented: .constant(saveError != nil), actions: {
                Button("OK") { saveError = nil }
            }, message: {
                Text(saveError ?? "")
            })
        }
    }

    private func save() {
        let clampedMM = min(max(radiusMM, 80), 130)
        let radiusM = Float(clampedMM / 1000)
        if let disc {
            disc.brand = brand
            disc.model = model
            disc.color = color
            disc.notes = notes
            disc.radius = radiusM
        } else {
            let newDisc = Disc(brand: brand, model: model, color: color, notes: notes, radius: radiusM)
            modelContext.insert(newDisc)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = "\(error)"
            print("[DiscFormView] save failed: \(error)")
        }
    }
}
