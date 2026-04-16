import SwiftUI

struct ThrowRow: View {
    let throwData: ThrowData

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(throwData.displayMPH + " mph")
                    .font(.headline)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Text(throwData.timestamp, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let disc = throwData.disc {
                        Text(disc.displayName)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Spacer()

            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(throwData.displayRPM)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                    Text("RPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text(throwData.displayHyzer)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                    Text("Hyzer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
