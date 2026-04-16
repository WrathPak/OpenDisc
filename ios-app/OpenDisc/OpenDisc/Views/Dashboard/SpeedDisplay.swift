import SwiftUI

struct SpeedDisplay: View {
    let mph: Float?

    var body: some View {
        VStack(spacing: 4) {
            Text(displayValue)
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(mph ?? 0)))
                .animation(.smooth(duration: 0.5), value: mph)

            Text("MPH")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 48)
        .glassEffect(.regular)
    }

    private var displayValue: String {
        guard let mph, mph >= 0 else { return "--" }
        return String(format: "%.1f", mph)
    }
}
