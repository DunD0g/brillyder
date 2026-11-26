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
                                    (tint ?? Color.white).opacity(tint == nil ? 0.12 : 0.34),
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
        } else if reduceTransparency {
            content
                .background(
                    Capsule()
                        .fill(BrillyPalette.hullBg)
                        .overlay(Capsule().fill(tint.opacity(0.28)))
                )
                .overlay(Capsule().strokeBorder(tint.opacity(0.65), lineWidth: 1.2))
        } else {
            content
                .background(Capsule().fill(tint.opacity(0.20)))
                .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
        }
    }
}

/// Groups neighboring Liquid Glass controls inside `GlassEffectContainer` on iOS 26+ so their edges fluidly morph.
public struct BrillyGlassCluster<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let style: SurfaceStyle
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    public init(style: SurfaceStyle, spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.style = style
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if style == .liquidGlass && !reduceTransparency {
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

    @ViewBuilder
    func brillySoftScrollEdge() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func brillyTabBarChrome(_ style: SurfaceStyle) -> some View {
        #if os(iOS)
        if style == .liquidGlass {
            if #available(iOS 26.0, *) {
                self.toolbarBackgroundVisibility(.automatic, for: .tabBar)
            } else {
                self
                    .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
            }
        } else {
            self
                .toolbarBackground(Color(hex: 0x0E121A).opacity(0.94), for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
        #else
        self
        #endif
    }
}

/// Crisp native tactile scale-down press style (`scaleEffect(0.98)`) for navigation pills and primary controls.
public struct BrillyPressScaleStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private struct BrillyPressObserverButtonStyle: ButtonStyle {
    let onPressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.78), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressChanged(pressed)
            }
    }
}

/// Tap for a single step, or press & hold (`>= 260ms`) to turbo-scrub rapidly with progressive acceleration
/// (`110ms` -> `65ms` -> `40ms` per tick). Uses `ButtonStyle.isPressed` so it never interferes with `ScrollView` or VoiceOver.
public struct BrillyTurboStepButton<Label: View>: View {
    private let onSingleStep: () -> Void
    private let onTurboStep: (_ tickIndex: Int) -> Bool
    private let onTurboStateChanged: ((Bool) -> Void)?
    private let label: (_ isTurbo: Bool) -> Label

    @State private var holdTask: Task<Void, Never>? = nil
    @State private var holdGeneration: Int = 0
    @State private var isTurbo: Bool = false
    @State private var didFireTurbo: Bool = false

    public init(
        onSingleStep: @escaping () -> Void,
        onTurboStep: @escaping (_ tickIndex: Int) -> Bool,
        onTurboStateChanged: ((Bool) -> Void)? = nil,
        @ViewBuilder label: @escaping (_ isTurbo: Bool) -> Label
    ) {
        self.onSingleStep = onSingleStep
        self.onTurboStep = onTurboStep
        self.onTurboStateChanged = onTurboStateChanged
        self.label = label
    }

    public var body: some View {
        Button {
            if didFireTurbo {
                didFireTurbo = false
                return
            }
            onSingleStep()
        } label: {
            label(isTurbo)
        }
        .buttonStyle(BrillyPressObserverButtonStyle { pressed in
            if pressed {
                startHoldTimer()
            } else {
                stopHoldTimer()
            }
        })
        .onDisappear {
            stopHoldTimer()
        }
    }

    private func startHoldTimer() {
        holdTask?.cancel()
        holdGeneration &+= 1
        let gen = holdGeneration
        didFireTurbo = false
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled && holdGeneration == gen else { return }
            isTurbo = true
            didFireTurbo = true
            onTurboStateChanged?(true)

            var tick = 0
            while !Task.isCancelled && holdGeneration == gen {
                let progressed = onTurboStep(tick)
                if !progressed { break }
                tick += 1
                let delayMs: Int = tick < 4 ? 110 : (tick < 12 ? 65 : 40)
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
            guard !Task.isCancelled && holdGeneration == gen else { return }
            isTurbo = false
            onTurboStateChanged?(false)
        }
    }

    private func stopHoldTimer() {
        holdGeneration &+= 1
        holdTask?.cancel()
        holdTask = nil
        if isTurbo {
            isTurbo = false
            onTurboStateChanged?(false)
        }
    }
}
