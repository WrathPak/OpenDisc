import SwiftUI

struct AngleIndicator: View {
    let angle: Float
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 44, height: 44)

                Rectangle()
                    .fill(angleColor)
                    .frame(width: 30, height: 3)
                    .rotationEffect(.degrees(Double(angle)))
            }

            Text(String(format: "%.1f", angle) + "\u{00B0}")
                .font(.caption2)
                .fontWeight(.semibold)
                .monospacedDigit()

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var angleColor: Color {
        let absAngle = abs(angle)
        if absAngle < 5 { return .green }
        if absAngle < 15 { return .yellow }
        return .orange
    }
}
