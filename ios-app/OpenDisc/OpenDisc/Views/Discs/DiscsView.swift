import SwiftUI
import SwiftData

struct DiscsView: View {
    @Query(sort: \Disc.brand) private var discs: [Disc]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddDisc = false

    var body: some View {
        Group {
            if discs.isEmpty {
                emptyState
            } else {
                discList
            }
        }
        .navigationTitle("My Discs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") {
                    showingAddDisc = true
                }
            }
        }
        .sheet(isPresented: $showingAddDisc) {
            DiscFormView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No discs added")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add your discs to track throws per disc")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Button("Add Disc") { showingAddDisc = true }
                .buttonStyle(.glass)
                .padding(.top, 8)
        }
    }

    private var discList: some View {
        List {
            ForEach(discs) { disc in
                NavigationLink(destination: DiscDetailView(disc: disc)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(disc.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                if !disc.color.isEmpty {
                                    Text(disc.color)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(disc.throws_.count) throws")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .onDelete(perform: deleteDiscs)
        }
    }

    private func deleteDiscs(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(discs[index])
        }
    }
}
