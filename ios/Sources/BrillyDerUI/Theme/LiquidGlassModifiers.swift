import SwiftUI

/// Authentic iOS 26 / macOS 26 Liquid Glass surface modifier with seamless fallback to
/// Cosmic Minimalist hull styling (and full Reduce Transparency accessibility support).
public struct BrillySurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let style: SurfaceStyle
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    public func body(content: Content) -> some View {
        if style == .liquidGlass && !reduceTransparency {
            if #available(iOS 26.0, macOS 26.0, *) {
                let baseGlass: Glass = {
                    var g = Glass.regular
                    if let tint {
                        g = g.tint(tint.opacity(0.24))
                    }
                    if interactive {
                        g = g.interactive()
                    }
                    return g
                }()
                content
                    .glassEffect(baseGlass, in: .rect(cornerRadius: cornerRadius))
            } else {
                // Pre-iOS 26 frosted Liquid Glass fallback
                content
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill((tint ?? BrillyPalette.brillyTeal).opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.32), Color.white.opacity(0.06)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
            }
        } else {
            // Cosmic Minimalist hull card (#0F172A + crisp subtle border)
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(BrillyPalette.hullBg.opacity(reduceTransparency ? 1.0 : 0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(
                                    (tint ?? Color.white).opacity(tint == nil ? 0.10 : 0.30),
                                    lineWidth: 1
                                )
                        )
                )
        }
    }
}

public struct BrillyCapsuleButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let style: SurfaceStyle
    let tint: Color

    public func body(content: Content) -> some View {
        if style == .liquidGlass && !reduceTransparency {
            if #available(iOS 26.0, macOS 26.0, *) {
                content
                    .glassEffect(.regular.tint(tint.opacity(0.35)).interactive(), in: .capsule)
            } else {
                content
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().fill(tint.opacity(0.22)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            }
        } else {
            content
                .background(Capsule().fill(tint.opacity(0.20)))
                .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
        }
    }
}

/// Groups neighboring Liquid Glass controls inside `GlassEffectContainer` on iOS 26+ so their edges fluidly morph.
public struct BrillyGlassCluster<Content: View>: View {
    let style: SurfaceStyle
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    public init(style: SurfaceStyle, spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.style = style
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if style == .liquidGlass {
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) {
                    content()
                }
            } else {
                content()
            }
        } else {
            content()
        }
    }
}

/// Rich dark cosmic background that gives Liquid Glass surfaces real luminous depth to refract.
public struct CosmicVoidBackdrop: View {
    let style: SurfaceStyle

    public init(style: SurfaceStyle) {
        self.style = style
    }

    public var body: some View {
        ZStack {
            BrillyPalette.voidBg.ignoresSafeArea()
            if style == .liquidGlass {
                // Soft ambient aurora orbs for iOS 26 Liquid Glass optical refraction
                RadialGradient(
                    colors: [BrillyPalette.brillyTeal.opacity(0.22), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 360
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [BrillyPalette.warpPurple.opacity(0.20), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 400
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [BrillyPalette.blunderRose.opacity(0.10), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 340
                )
                .ignoresSafeArea()
            } else {
                RadialGradient(
                    colors: [BrillyPalette.hullBg.opacity(0.75), BrillyPalette.voidBg],
                    center: .top,
                    startRadius: 20,
                    endRadius: 520
                )
                .ignoresSafeArea()
            }
        }
    }
}

public extension View {
    func brillySurface(
        _ style: SurfaceStyle,
        cornerRadius: CGFloat = 20,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(BrillySurfaceModifier(style: style, cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    func brillyGlassPill(_ style: SurfaceStyle, tint: Color = BrillyPalette.brillyTeal) -> some View {
        modifier(BrillyCapsuleButtonModifier(style: style, tint: tint))
    }
}
