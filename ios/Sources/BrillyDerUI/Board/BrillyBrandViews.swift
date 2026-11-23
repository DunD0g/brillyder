import SwiftUI

/// Official Brilly/Der split-crown emblem (cyan `!!` left / rose `??` right inside a cosmic ring),
/// matching the Web PWA `icon.svg` and iOS AppIcon.
public struct BrillyLogoMark: View {
    public let size: CGFloat
    public let circular: Bool

    public init(size: CGFloat = 30, circular: Bool = true) {
        self.size = size
        self.circular = circular
    }

    public var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height)
            let ox = (sz.width - s) / 2
            let oy = (sz.height - s) / 2
            ctx.translateBy(x: ox, y: oy)
            let k = s / 100.0

            // 1. Deep Cosmic Medallion Fill + Subtle Split Ambient Glow
            let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
            let bgPath: Path = circular
                ? Path(ellipseIn: bgRect)
                : Path(roundedRect: bgRect, cornerRadius: s * 0.24)

            ctx.fill(bgPath, with: .color(Color(hex: 0x0B1222)))
            ctx.fill(
                bgPath,
                with: .radialGradient(
                    Gradient(colors: [Color(hex: 0x22D3EE).opacity(0.26), .clear]),
                    center: CGPoint(x: 24 * k, y: 34 * k),
                    startRadius: 2 * k,
                    endRadius: 52 * k
                )
            )
            ctx.fill(
                bgPath,
                with: .radialGradient(
                    Gradient(colors: [Color(hex: 0xFB7185).opacity(0.26), .clear]),
                    center: CGPoint(x: 76 * k, y: 34 * k),
                    startRadius: 2 * k,
                    endRadius: 52 * k
                )
            )

            // 2. Signature Split Outer Arcs (Left Cyan / Right Rose)
            let arcRadius = 41.5 * k
            let center = CGPoint(x: 50 * k, y: 50 * k)
            let arcWidth = max(1.8, 3.8 * k)

            var leftArc = Path()
            leftArc.addArc(
                center: center,
                radius: arcRadius,
                startAngle: .degrees(102),
                endAngle: .degrees(258),
                clockwise: false
            )
            ctx.stroke(
                leftArc,
                with: .color(Color(hex: 0x22D3EE).opacity(0.75)),
                style: StrokeStyle(lineWidth: arcWidth, lineCap: .round)
            )

            var rightArc = Path()
            rightArc.addArc(
                center: center,
                radius: arcRadius,
                startAngle: .degrees(-78),
                endAngle: .degrees(78),
                clockwise: false
            )
            ctx.stroke(
                rightArc,
                with: .color(Color(hex: 0xFB7185).opacity(0.75)),
                style: StrokeStyle(lineWidth: arcWidth, lineCap: .round)
            )

            // 3. Split Crown Geometry (Left Half Teal-Cyan / Right Half Blunder-Rose)
            var crown = Path()
            crown.move(to: CGPoint(x: 27 * k, y: 65 * k))
            crown.addLine(to: CGPoint(x: 32 * k, y: 36 * k))
            crown.addLine(to: CGPoint(x: 45 * k, y: 48 * k))
            crown.addLine(to: CGPoint(x: 50 * k, y: 26 * k))
            crown.addLine(to: CGPoint(x: 55 * k, y: 48 * k))
            crown.addLine(to: CGPoint(x: 68 * k, y: 36 * k))
            crown.addLine(to: CGPoint(x: 73 * k, y: 65 * k))
            crown.closeSubpath()

            let baseBand = Path(
                roundedRect: CGRect(x: 25 * k, y: 69 * k, width: 50 * k, height: 10.5 * k),
                cornerRadius: 3.5 * k
            )

            let splitGradient = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [
                    .init(color: Color(hex: 0x2DD4BF), location: 0.00),
                    .init(color: Color(hex: 0x06B6D4), location: 0.495),
                    .init(color: Color(hex: 0xF43F5E), location: 0.505),
                    .init(color: Color(hex: 0xFB7185), location: 1.00),
                ]),
                startPoint: CGPoint(x: 25 * k, y: 50 * k),
                endPoint: CGPoint(x: 75 * k, y: 50 * k)
            )

            ctx.fill(crown, with: splitGradient)
            ctx.fill(baseBand, with: splitGradient)
            ctx.stroke(crown, with: .color(Color.white.opacity(0.28)), lineWidth: max(0.6, 1.0 * k))
            ctx.stroke(baseBand, with: .color(Color.white.opacity(0.28)), lineWidth: max(0.6, 1.0 * k))

            // 4. Tiny glowing !! & ?? accents when large enough to read crisply
            if s >= 26 {
                let markSize = max(7.0, 12.5 * k)
                let brilText = Text("!!")
                    .font(.system(size: markSize, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0x22D3EE))
                let derText = Text("??")
                    .font(.system(size: markSize, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFB7185))
                ctx.draw(brilText, at: CGPoint(x: 27 * k, y: 27 * k), anchor: .center)
                ctx.draw(derText, at: CGPoint(x: 73 * k, y: 27 * k), anchor: .center)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Signature dual-tone `Brilly/Der` wordmark matching the Web PWA palette
/// (luminous teal `Brilly` + crisp tilted `/` divider + blunder-rose `Der`).
public struct BrillyWordmarkView: View {
    public let fontSize: CGFloat
    public let uppercase: Bool
    public let showSlash: Bool
    public let tracking: CGFloat

    public init(
        fontSize: CGFloat = 30,
        uppercase: Bool = false,
        showSlash: Bool = true,
        tracking: CGFloat = -0.3
    ) {
        self.fontSize = fontSize
        self.uppercase = uppercase
        self.showSlash = showSlash
        self.tracking = tracking
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: showSlash ? max(1, fontSize * 0.04) : 0) {
            Text(uppercase ? "BRILLY" : "Brilly")
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .tracking(tracking)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: 0x5EEAD4), Color(hex: 0x2DD4BF), Color(hex: 0x06B6D4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if showSlash {
                Text("/")
                    .font(.system(size: fontSize * 0.92, weight: .heavy, design: .rounded))
                    .italic()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hex: 0x67E8F9).opacity(0.90),
                                Color.white.opacity(0.75),
                                Color(hex: 0xFDA4AF).opacity(0.90),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.horizontal, max(0.5, fontSize * 0.02))
            }

            Text(uppercase ? "DER" : "Der")
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .tracking(tracking)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: 0xFDA4AF), Color(hex: 0xFB7185), Color(hex: 0xF43F5E)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BrillyDer")
    }
}
