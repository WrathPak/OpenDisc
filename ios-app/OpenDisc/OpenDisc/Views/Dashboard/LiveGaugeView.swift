import SwiftUI

struct LiveGaugeView: View {
    let value: Float
    let maxValue: Float
    let label: String
    let unit: String
    var tint: Color = .blue

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: CGFloat(min(value / maxValue, 1.0)) * 0.75)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.smooth(duration: 0.3), value: value)

                VStack(spacing: 0) {
                    Text(String(format: "%.0f", value))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(value)))

                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)

            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassEffect(.regular.tint(tint.opacity(0.15)))
    }
}
