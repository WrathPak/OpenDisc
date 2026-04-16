import SwiftUI
import SwiftData

struct DiscPicker: View {
    @Query(sort: \Disc.brand) private var discs: [Disc]
    @Binding var selectedDisc: Disc?
    @State private var showingAddDisc = false

    var body: some View {
        Menu {
            Button {
                selectedDisc = nil
            } label: {
                if selectedDisc == nil {
                    Label("No disc", systemImage: "checkmark")
                } else {
                    Text("No disc")
                }
            }

            Divider()

            ForEach(discs) { disc in
                Button {
                    selectedDisc = disc
                } label: {
                    if selectedDisc?.persistentModelID == disc.persistentModelID {
                        Label(disc.displayName, systemImage: "checkmark")
                    } else {
                        Text(disc.displayName)
                    }
                }
            }

            Divider()

            Button {
                showingAddDisc = true
            } label: {
                Label("Add New Disc...", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "opticaldisc")
                    .font(.caption)
                Text(selectedDisc?.displayName ?? "No disc")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive())
        }
        .sheet(isPresented: $showingAddDisc) {
            DiscFormView()
        }
    }
}
