import SwiftUI

struct GlassCard<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding()
            .glassEffect(tint.map { .regular.tint($0) } ?? .regular)
    }
}
