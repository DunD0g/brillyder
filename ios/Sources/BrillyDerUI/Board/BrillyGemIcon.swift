import SwiftUI

/// Custom faceted Brilliant Gem icon (inspired by Lucide's Gem / BrillyDer's !! crystal),
/// with crisp beveled facets and specular highlights.
public struct BrillyGemIcon: View {
    let size: CGFloat
    let color: Color

    public init(size: CGFloat = 18, color: Color = BrillyPalette.brillyTeal) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { ctx, sz in
            let w = sz.width
            let h = sz.height

            let topL = CGPoint(x: w * 0.24, y: h * 0.14)
            let topR = CGPoint(x: w * 0.76, y: h * 0.14)
            let midL = CGPoint(x: w * 0.06, y: h * 0.40)
            let midR = CGPoint(x: w * 0.94, y: h * 0.40)
            let bot  = CGPoint(x: w * 0.50, y: h * 0.90)
            let cL   = CGPoint(x: w * 0.34, y: h * 0.40)
            let cR   = CGPoint(x: w * 0.66, y: h * 0.40)

            var outer = Path()
            outer.move(to: topL)
            outer.addLine(to: topR)
            outer.addLine(to: midR)
            outer.addLine(to: bot)
            outer.addLine(to: midL)
            outer.closeSubpath()

            ctx.fill(
                outer,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.95),
                        color,
                        color.opacity(0.68),
                    ]),
                    startPoint: CGPoint(x: w * 0.2, y: h * 0.1),
                    endPoint: CGPoint(x: w * 0.85, y: h * 0.92)
                )
            )

            // Bright crown table facet
            var crown = Path()
            crown.move(to: topL)
            crown.addLine(to: topR)
            crown.addLine(to: cR)
            crown.addLine(to: cL)
            crown.closeSubpath()
            ctx.fill(crown, with: .color(Color.white.opacity(0.42)))

            // Deeper right pavilion shadow facet
            var rightPav = Path()
            rightPav.move(to: cR)
            rightPav.addLine(to: midR)
            rightPav.addLine(to: bot)
            rightPav.closeSubpath()
            ctx.fill(rightPav, with: .color(Color.black.opacity(0.22)))

            // Crisp internal facet lines only (outer perimeter stroked once below)
            var facets = Path()
            facets.move(to: midL); facets.addLine(to: midR)
            facets.move(to: topL); facets.addLine(to: cL); facets.addLine(to: bot)
            facets.move(to: topR); facets.addLine(to: cR); facets.addLine(to: bot)

            ctx.stroke(facets, with: .color(Color.white.opacity(0.55)), lineWidth: max(0.75, w * 0.055))
            ctx.stroke(outer, with: .color(Color.white.opacity(0.84)), style: StrokeStyle(lineWidth: max(0.9, w * 0.065), lineJoin: .round))
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.45), radius: size * 0.18, y: 0.5)
        .accessibilityHidden(true)
    }
}
