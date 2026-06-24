import SwiftUI

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 0
    var isCircle: Bool = false
    var fallback: AnyShapeStyle

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if isCircle {
                content.glassEffect(.regular, in: .circle)
            } else if cornerRadius > 0 {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular)
            }
        } else {
            if isCircle {
                content.background(fallback, in: .circle)
            } else if cornerRadius > 0 {
                content.background(fallback, in: .rect(cornerRadius: cornerRadius))
            } else {
                content.background(fallback)
            }
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

struct GlassBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(
                .regular,
                in: .rect(cornerRadii: .init(topLeading: 12, bottomLeading: 0, bottomTrailing: 0, topTrailing: 12))
            )
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

    func glassBar() -> some View {
        modifier(GlassBar())
    }

    func glassBackground(cornerRadius: CGFloat = 0, fallback: some ShapeStyle = Color.gray.opacity(0.06)) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, fallback: AnyShapeStyle(fallback)))
    }

    func glassCircle(fallback: some ShapeStyle = Color.primary.opacity(0.1)) -> some View {
        modifier(GlassBackground(isCircle: true, fallback: AnyShapeStyle(fallback)))
    }
}
