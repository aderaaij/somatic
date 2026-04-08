import SwiftUI

// MARK: - Card Modifier (Liquid Glass)

struct CardModifier: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .glassEffect(.regular.tint(tint ?? .clear), in: .rect(cornerRadius: 16))
    }
}

extension View {
    func cardStyle(tint: Color? = nil) -> some View {
        modifier(CardModifier(tint: tint))
    }
}
