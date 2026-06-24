import SwiftUI

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 0
    var fallback: AnyShapeStyle

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if cornerRadius > 0 {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular)
            }
        } else {
            content.background(fallback)
        }
    }
}

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(Color.gray.opacity(0.06))
        }
    }
}

struct GlassMaterial: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular)
        } else {
            content.background(.ultraThinMaterial)
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    func glassMaterial() -> some View {
        modifier(GlassMaterial())
    }

    func glassBackground(cornerRadius: CGFloat = 0, fallback: some ShapeStyle = Color.gray.opacity(0.06)) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, fallback: AnyShapeStyle(fallback)))
    }
}
