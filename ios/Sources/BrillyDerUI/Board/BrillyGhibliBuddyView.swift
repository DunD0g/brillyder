import SwiftUI

/// Crisp, native emoji-style reaction medallion for the default `Brilly/Der` theme:
/// - Brilliant moves: mind-blown exploding head (`🤯`) with glowing sparkles ("Very nice, Brilly!!")
/// - Blunder moves: comical facepalm (`🤦`) with comic shock lines & sweat drop ("Blun-DER!!")
public struct BrillyGhibliBuddyView: View {
    public let mood: BrillyAlienMood
    public let size: CGFloat

    public init(mood: BrillyAlienMood = .brilliant, size: CGFloat = 68) {
        self.mood = mood
        self.size = size
    }

    private var isBlunder: Bool {
        mood == .blunder
    }

    private var isNegativeMood: Bool {
        mood == .blunder || mood == .mistake
    }

    private var emojiGlyph: String {
        switch mood {
        case .brilliant:
            return "🤯"
        case .great:
            return "🔥"
        case .best:
            return "👍"
        case .book:
            return "📖"
        case .mistake:
            return "😬"
        case .blunder:
            return "🤦"
        }
    }

    private var ringColors: [Color] {
        if isNegativeMood {
            return [BrillyPalette.blunderRose, Color(hex: 0xF97316), BrillyPalette.blunderRose.opacity(0.65)]
        }
        return [BrillyPalette.brillyTeal, Color(hex: 0x67E8F9), BrillyPalette.goldAmber.opacity(0.85)]
    }

    private var innerFill: [Color] {
        if isNegativeMood {
            return [BrillyPalette.blunderRose.opacity(0.28), Color(hex: 0x1A0F1E)]
        }
        return [BrillyPalette.brillyTeal.opacity(0.26), Color(hex: 0x0A1628)]
    }

    public var body: some View {
        ZStack {
            // Soft outer aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [mood.accentColor.opacity(0.32), mood.accentColor.opacity(0.0)],
                        center: .center,
                        startRadius: size * 0.22,
                        endRadius: size * 0.56
                    )
                )
                .frame(width: size * 1.12, height: size * 1.12)

            // Dark-glass circular medallion
            Circle()
                .fill(
                    RadialGradient(
                        colors: innerFill,
                        center: UnitPoint(x: 0.35, y: 0.28),
                        startRadius: size * 0.05,
                        endRadius: size * 0.54
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: ringColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1.8, size * 0.035)
                        )
                )
                .shadow(color: mood.accentColor.opacity(0.38), radius: 8, y: 2)

            // Crisp native Apple emoji
            Text(emojiGlyph)
                .font(.system(size: size * 0.56))
                .rotationEffect(.degrees(isBlunder ? 5 : (mood == .best ? -6 : 0)))
                .shadow(color: Color.black.opacity(0.35), radius: 3, y: 2)

            // Expressive vector sparkles (positive) or comic sweat/shock accents (negative)
            Canvas { ctx, canvasSize in
                let s = min(canvasSize.width, canvasSize.height) / 100.0
                if isNegativeMood {
                    // Comic shock lines top-left
                    var lines = Path()
                    lines.move(to: CGPoint(x: 16 * s, y: 22 * s))
                    lines.addLine(to: CGPoint(x: 24 * s, y: 28 * s))
                    lines.move(to: CGPoint(x: 24 * s, y: 12 * s))
                    lines.addLine(to: CGPoint(x: 29 * s, y: 21 * s))
                    ctx.stroke(
                        lines,
                        with: .color(BrillyPalette.blunderRose.opacity(0.92)),
                        style: StrokeStyle(lineWidth: max(1.8, 2.8 * s), lineCap: .round)
                    )

                    // Classic cartoon blue sweat drop top-right
                    var drop = Path()
                    let dx = 79 * s
                    let dy = 16 * s
                    drop.move(to: CGPoint(x: dx, y: dy))
                    drop.addQuadCurve(to: CGPoint(x: dx - 6 * s, y: dy + 12 * s), control: CGPoint(x: dx - 7.5 * s, y: dy + 6 * s))
                    drop.addQuadCurve(to: CGPoint(x: dx + 6 * s, y: dy + 12 * s), control: CGPoint(x: dx, y: dy + 18 * s))
                    drop.addQuadCurve(to: CGPoint(x: dx, y: dy), control: CGPoint(x: dx + 7.5 * s, y: dy + 6 * s))
                    drop.closeSubpath()
                    ctx.fill(drop, with: .color(Color(hex: 0x7DD3FC)))
                    ctx.stroke(drop, with: .color(Color(hex: 0x0EA5E9)), lineWidth: max(0.8, 1.2 * s))
                } else {
                    // Crisp 4-point teal & gold sparkles
                    drawStar(in: &ctx, center: CGPoint(x: 80 * s, y: 20 * s), radius: 9.5 * s, color: Color(hex: 0xFDE047))
                    drawStar(in: &ctx, center: CGPoint(x: 19 * s, y: 26 * s), radius: 7.0 * s, color: Color(hex: 0x67E8F9))
                    drawStar(in: &ctx, center: CGPoint(x: 83 * s, y: 74 * s), radius: 5.5 * s, color: BrillyPalette.brillyTeal)
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func drawStar(in ctx: inout GraphicsContext, center: CGPoint, radius r: CGFloat, color: Color) {
        let inner = r * 0.28
        var star = Path()
        star.move(to: CGPoint(x: center.x, y: center.y - r))
        star.addLine(to: CGPoint(x: center.x + inner, y: center.y - inner))
        star.addLine(to: CGPoint(x: center.x + r, y: center.y))
        star.addLine(to: CGPoint(x: center.x + inner, y: center.y + inner))
        star.addLine(to: CGPoint(x: center.x, y: center.y + r))
        star.addLine(to: CGPoint(x: center.x - inner, y: center.y + inner))
        star.addLine(to: CGPoint(x: center.x - r, y: center.y))
        star.addLine(to: CGPoint(x: center.x - inner, y: center.y - inner))
        star.closeSubpath()
        ctx.fill(star, with: .color(color))
    }
}
