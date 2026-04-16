import SwiftUI

struct DiscFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var disc: Disc?

    @State private var brand: String = ""
    @State private var model: String = ""
    @State private var color: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Disc Info") {
                    TextField("Brand", text: $brand)
                    TextField("Model", text: $model)
                    TextField("Color (optional)", text: $color)
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
                }
            }
        }
    }

    private func save() {
        if let disc {
            disc.brand = brand
            disc.model = model
            disc.color = color
            disc.notes = notes
        } else {
            let newDisc = Disc(brand: brand, model: model, color: color, notes: notes)
            modelContext.insert(newDisc)
        }
        dismiss()
    }
}
