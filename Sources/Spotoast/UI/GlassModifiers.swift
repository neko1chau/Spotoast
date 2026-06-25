import SwiftUI

// MARK: - Shared edge highlight overlay

private struct GlassEdgeHighlight: ViewModifier {
    var cornerRadius: CGFloat
    var isCircle: Bool = false

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content.overlay(edgeStroke)
        }
    }

    @ViewBuilder
    private var edgeStroke: some View {
        let gradient = LinearGradient(
            colors: [.white.opacity(0.45), .white.opacity(0.05), .black.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        if isCircle {
            Circle().strokeBorder(gradient, lineWidth: 0.5)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(gradient, lineWidth: 0.5)
        }
    }
}

// MARK: - Modifiers

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 0
    var isCircle: Bool = false
    var fallback: AnyShapeStyle

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if isCircle {
                content.glassEffect(.regular.interactive(), in: .circle)
            } else if cornerRadius > 0 {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular.interactive())
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
    var tint: Color? = nil
    var clear: Bool = false

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            let base: Glass = clear ? .clear : .regular
            if let tint {
                content.glassEffect(base.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(base.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
                .modifier(GlassEdgeHighlight(cornerRadius: cornerRadius))
        }
    }
}

struct GlassMaterial: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive())
        } else {
            content.background(.ultraThinMaterial)
        }
    }
}

struct GlassBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(
                .clear.interactive(),
                in: .rect(cornerRadii: .init(topLeading: 12, bottomLeading: 0, bottomTrailing: 0, topTrailing: 12))
            )
        } else {
            content
                .background(.ultraThinMaterial)
                .modifier(GlassEdgeHighlight(cornerRadius: 12))
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 10, tint: Color? = nil, clear: Bool = false) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint, clear: clear))
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
