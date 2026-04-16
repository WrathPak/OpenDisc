import SwiftUI

struct ThrowTypePicker: View {
    @Binding var throwType: ThrowType
    @Binding var throwHand: ThrowHand

    var body: some View {
        HStack(spacing: 8) {
            // Hand picker
            Menu {
                ForEach(ThrowHand.allCases, id: \.self) { hand in
                    Button {
                        throwHand = hand
                    } label: {
                        if throwHand == hand {
                            Label(hand == .right ? "Right Hand" : "Left Hand", systemImage: "checkmark")
                        } else {
                            Text(hand == .right ? "Right Hand" : "Left Hand")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: throwHand == .right ? "hand.raised.fill" : "hand.raised.fill")
                    Text(throwHand.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive())
            }

            // Type picker
            Menu {
                ForEach(ThrowType.allCases, id: \.self) { type in
                    Button {
                        throwType = type
                    } label: {
                        if throwType == type {
                            Label(type.rawValue, systemImage: "checkmark")
                        } else {
                            Text(type.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: throwType == .backhand ? "arrow.counterclockwise" : "arrow.clockwise")
                        .font(.caption)
                    Text(throwType.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive())
            }
        }
    }
}
