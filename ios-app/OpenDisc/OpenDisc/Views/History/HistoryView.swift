import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \ThrowData.timestamp, order: .reverse) private var throws_: [ThrowData]
    @Environment(\.modelContext) private var modelContext
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if throws_.isEmpty {
                    emptyState
                } else {
                    throwList
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !throws_.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", systemImage: "trash") {
                            showingClearConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog("Clear all throw history?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                Button("Clear All", role: .destructive) {
                    clearHistory()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.disc.sports")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No throws yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Your throw history will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private var throwList: some View {
        List {
            ForEach(throws_) { throwData in
                NavigationLink(destination: ThrowDetailView(throwData: throwData)) {
                    ThrowRow(throwData: throwData)
                }
            }
            .onDelete(perform: deleteThrows)
        }
    }

    private func deleteThrows(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(throws_[index])
        }
    }

    private func clearHistory() {
        for throwData in throws_ {
            modelContext.delete(throwData)
        }
    }
}
