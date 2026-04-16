import SwiftUI

struct ConnectionStatusBar: View {
    let connectionState: ConnectionState
    let deviceState: DeviceState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)

            Spacer()

            if connectionState == .connected {
                Label(deviceState.displayName, systemImage: deviceState.systemImage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(deviceState.color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(statusColor.opacity(0.3)))
        .animation(.smooth, value: connectionState)
        .animation(.smooth, value: deviceState)
    }

    private var statusColor: Color {
        switch connectionState {
        case .connected:    .green
        case .reconnecting: .orange
        case .connecting:   .yellow
        default:            .red
        }
    }

    private var statusText: String {
        switch connectionState {
        case .connected:    "Connected"
        case .reconnecting: "Reconnecting..."
        case .connecting:   "Connecting..."
        case .scanning:     "Scanning..."
        case .disconnected: "Disconnected"
        }
    }
}
