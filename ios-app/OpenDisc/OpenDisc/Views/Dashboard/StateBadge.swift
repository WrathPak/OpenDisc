import SwiftUI

struct StateBadge: View {
    let state: DeviceState

    var body: some View {
        Label(state.displayName, systemImage: state.systemImage)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(state.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(state.color.opacity(0.3)))
            .animation(.smooth, value: state)
    }
}
