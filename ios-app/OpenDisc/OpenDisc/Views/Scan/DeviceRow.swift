import SwiftUI

struct DeviceRow: View {
    let device: DiscoveredPeripheral
    let isConnecting: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "disc")
                .font(.title2)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                Text(signalDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnecting {
                ProgressView()
            } else {
                signalBars
            }
        }
        .padding(.vertical, 4)
    }

    private var signalBars: some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < signalStrength ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(6 + i * 4))
            }
        }
    }

    private var signalStrength: Int {
        switch device.rssi {
        case -50...0:    4
        case -65..<(-50): 3
        case -80..<(-65): 2
        default:         1
        }
    }

    private var signalDescription: String {
        switch signalStrength {
        case 4: "Excellent signal"
        case 3: "Good signal"
        case 2: "Fair signal"
        default: "Weak signal"
        }
    }
}
