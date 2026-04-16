import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    var tint: Color? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassEffect(tint.map { .regular.tint($0.opacity(0.2)) } ?? .regular)
    }
}
