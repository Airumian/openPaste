import SwiftUI

/// Liquid Glass on macOS 26+, frosted material on older systems.
extension View {
    @ViewBuilder
    func liquidGlass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false)
        -> some View
    {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    /// Lets glass shapes with the same id morph into each other when they move (e.g. the selected tab).
    @ViewBuilder
    func liquidGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

/// Groups nearby glass shapes so they blend and morph together.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
