import SwiftUI

private let cardRadius: CGFloat = 10

// MARK: - Card Modifier (Liquid Glass)

/// Used for top-level containers (plan overview, day detail wrapper, banners)
struct CardModifier: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
            .glassEffect(.regular.tint(tint ?? .clear), in: .rect(cornerRadius: cardRadius))
    }
}

/// Used for individual items inside a container (workout rows, list items)
struct InnerCardModifier: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .stroke(
                        (tint ?? Color.primary).opacity(tint != nil ? 0.2 : 0.1),
                        lineWidth: 0.5
                    )
            }
    }
}

extension View {
    func cardStyle(tint: Color? = nil) -> some View {
        modifier(CardModifier(tint: tint))
    }

    func innerCardStyle(tint: Color? = nil) -> some View {
        modifier(InnerCardModifier(tint: tint))
    }
}
