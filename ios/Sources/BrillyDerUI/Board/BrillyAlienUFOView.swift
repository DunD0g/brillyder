import SwiftUI
import BrillyDerCore

/// Expressive mood for BrillyDer's signature cosmic Alien UFO mascot.
public enum BrillyAlienMood: String, Sendable, Equatable, CaseIterable {
    case brilliant
    case great
    case best
    case book
    case mistake
    case blunder

    public static func from(classification: MoveClassification?) -> BrillyAlienMood {
        switch classification {
        case .brilliant, .none:
            return .brilliant
        case .great:
            return .great
        case .best, .excellent:
            return .best
        case .book:
            return .book
        case .inaccuracy, .mistake:
            return .mistake
        case .blunder:
            return .blunder
        }
    }

    public var accentColor: Color {
        switch self {
        case .brilliant: return Color(hex: 0x22D3EE)
        case .great:     return Color(hex: 0x3B82F6)
        case .best:      return Color(hex: 0x22C55E)
        case .book:      return Color(hex: 0xF59E0B)
        case .mistake:   return Color(hex: 0xF97316)
        case .blunder:   return Color(hex: 0xFB7185)
        }
    }

    public var secondaryGlow: Color {
        switch self {
        case .brilliant: return Color(hex: 0xA855F7)
        case .great:     return Color(hex: 0x2DD4BF)
        case .best:      return Color(hex: 0x2DD4BF)
        case .book:      return Color(hex: 0xFB923C)
        case .mistake:   return Color(hex: 0xEF4444)
        case .blunder:   return Color(hex: 0xE11D48)
        }
    }

    public var saucerDark: Color {
        switch self {
        case .brilliant: return Color(hex: 0x0284C7)
        case .great:     return Color(hex: 0x1D4ED8)
        case .best:      return Color(hex: 0x15803D)
        case .book:      return Color(hex: 0xB45309)
        case .mistake:   return Color(hex: 0xC2410C)
        case .blunder:   return Color(hex: 0xBE123C)
        }
    }

    public var alienLight: Color {
        switch self {
        case .brilliant: return Color(hex: 0xBEF264)
        case .great:     return Color(hex: 0x6EE7B7)
        case .best:      return Color(hex: 0xA3E635)
        case .book:      return Color(hex: 0xFDE68A)
        case .mistake:   return Color(hex: 0xFDBA74)
        case .blunder:   return Color(hex: 0xFDA4AF)
        }
    }

    public var alienDark: Color {
        switch self {
        case .brilliant: return Color(hex: 0x22C55E)
        case .great:     return Color(hex: 0x10B981)
        case .best:      return Color(hex: 0x16A34A)
        case .book:      return Color(hex: 0xF59E0B)
        case .mistake:   return Color(hex: 0xEA580C)
        case .blunder:   return Color(hex: 0xF43F5E)
        }
    }

    public var portholeColor: Color {
        switch self {
        case .brilliant, .great, .best, .book:
            return Color(hex: 0xFDE047)
        case .mistake:
            return Color(hex: 0xFDBA74)
        case .blunder:
            return Color(hex: 0xFECDD3)
        }
    }

    public var cosmicTag: String {
        switch self {
        case .brilliant: return "GALAXY-BRAIN SIGNAL"
        case .great:     return "PRECISION STRIKE"
        case .best:      return "MOTHERSHIP APPROVED"
        case .book:      return "STAR-CHART THEORY"
        case .mistake:   return "ORBITAL DRIFT"
        case .blunder:   return "HULL BREACH ALERT"
        }
    }

    public var classicTag: String {
        switch self {
        case .brilliant: return "BRILLIANT MOVE"
        case .great:     return "GREAT MOVE"
        case .best:      return "BEST MOVE"
        case .book:      return "BOOK THEORY"
        case .mistake:   return "CRITICAL MOMENT"
        case .blunder:   return "BLUNDER REVIEW"
        }
    }
}

/// Curated witty cosmic & classic quips for Share Cards and live celebrations.
public enum BrillyShareQuips {
    public static func pool(for mood: BrillyAlienMood, vibe: VibeMode) -> [String] {
        switch (mood, vibe) {
        case (.brilliant, .cosmic):
            return [
                "Beam me up, Magnus — that sacrifice isn't from this planet!",
                "Area 51 called. They want their tactics back.",
                "Humans aren't supposed to calculate that!",
                "Certified Galaxy-Brain Sacrifice!",
                "Stockfish just filed a UFO sighting report.",
                "NASA renamed a constellation after that move.",
                "The aliens graded it: \"Finally, a worthy opponent.\"",
                "Somewhere, a grandmaster just spilled their coffee.",
            ]
        case (.brilliant, .classic):
            return [
                "Brilliant sacrifice — the sharpest move on the board.",
                "Tactical masterpiece — material offered for decisive initiative.",
                "Outstanding calculation — engine's top sacrificial resource.",
            ]
        case (.great, .cosmic):
            return [
                "Only move in the galaxy — locked directly on target!",
                "Warp-drive precision. Zero margin for error.",
                "Mothership scanners confirm: surgical tactical strike.",
                "Threaded the needle through an asteroid field.",
            ]
        case (.great, .classic):
            return [
                "Great move — the only winning resource in a razor-sharp position.",
                "Decisive accuracy — turns the game firmly in your favor.",
            ]
        case (.best, .cosmic):
            return [
                "Pure engine telemetry — smooth orbital control.",
                "Mothership approves: top-line calculation.",
                "Clean trajectory right down the laser sight.",
            ]
        case (.best, .classic):
            return [
                "Top engine move — clean, principled chess.",
                "Exact calculation keeping maximum pressure on the board.",
            ]
        case (.book, .cosmic):
            return [
                "Straight out of the galactic opening codex.",
                "Star-chart theory locked in — smooth launch!",
            ]
        case (.book, .classic):
            return [
                "Established opening theory — strong, principled setup.",
            ]
        case (.mistake, .cosmic):
            return [
                "Slight orbital drift — recalibrate thrusters!",
                "A bit of turbulence in the asteroid belt.",
                "Even starships miss a turn now and then.",
            ]
        case (.mistake, .classic):
            return [
                "A key turning point — study the engine's sharper continuation.",
            ]
        case (.blunder, .cosmic):
            return [
                "Houston, we dropped a piece.",
                "The UFO is facepalming. Slowly.",
                "Beam malfunction — material did not survive transport.",
                "Mission Control: \"We strongly recommend not doing that.\"",
                "Alien scan complete: \"Yep, that one hurts.\"",
            ]
        case (.blunder, .classic):
            return [
                "Serious blunder — check the refutation and lock in the tactic.",
                "Decisive swing — review the best defensive move.",
            ]
        }
    }

    public static func quip(for mood: BrillyAlienMood, vibe: VibeMode, index: Int) -> String {
        let items = pool(for: mood, vibe: vibe)
        guard !items.isEmpty else { return "" }
        let safeIdx = ((index % items.count) + items.count) % items.count
        return items[safeIdx]
    }
}

/// Bespoke vector SwiftUI illustration of BrillyDer's Alien UFO mascot with tractor beam,
/// glowing porthole lights, translucent dome, expressive eyes, and floating cosmic sparkles.
public struct BrillyAlienUFOView: View {
    public let mood: BrillyAlienMood
    public let size: CGFloat
    public let showBeam: Bool

    public init(mood: BrillyAlienMood = .brilliant, size: CGFloat = 88, showBeam: Bool = true) {
        self.mood = mood
        self.size = size
        self.showBeam = showBeam
    }

    public var body: some View {
        Canvas { ctx, canvasSize in
            let sx = canvasSize.width / 120.0
            let sy = canvasSize.height / 112.0
            let s = min(sx, sy)
            let ox = (canvasSize.width - 120.0 * s) / 2.0
            let oy = (canvasSize.height - 112.0 * s) / 2.0

            ctx.translateBy(x: ox, y: oy)
            ctx.scaleBy(x: s, y: s)

            // 1. Soft atmospheric radial aura behind the UFO
            let auraRect = CGRect(x: 10, y: 6, width: 100, height: 84)
            ctx.fill(
                Path(ellipseIn: auraRect),
                with: .radialGradient(
                    Gradient(colors: [mood.accentColor.opacity(0.32), mood.accentColor.opacity(0.0)]),
                    center: CGPoint(x: 60, y: 46),
                    startRadius: 6,
                    endRadius: 50
                )
            )

            // 2. Luminous Tractor Beam
            if showBeam {
                var outerBeam = Path()
                outerBeam.move(to: CGPoint(x: 42, y: 58))
                outerBeam.addLine(to: CGPoint(x: 18, y: 110))
                outerBeam.addLine(to: CGPoint(x: 102, y: 110))
                outerBeam.addLine(to: CGPoint(x: 78, y: 58))
                outerBeam.closeSubpath()
                ctx.fill(
                    outerBeam,
                    with: .linearGradient(
                        Gradient(colors: [
                            mood.accentColor.opacity(0.56),
                            mood.accentColor.opacity(0.18),
                            mood.accentColor.opacity(0.0),
                        ]),
                        startPoint: CGPoint(x: 60, y: 58),
                        endPoint: CGPoint(x: 60, y: 110)
                    )
                )

                var innerBeam = Path()
                innerBeam.move(to: CGPoint(x: 51, y: 59))
                innerBeam.addLine(to: CGPoint(x: 38, y: 108))
                innerBeam.addLine(to: CGPoint(x: 82, y: 108))
                innerBeam.addLine(to: CGPoint(x: 69, y: 59))
                innerBeam.closeSubpath()
                ctx.fill(
                    innerBeam,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(0.36),
                            mood.accentColor.opacity(0.0),
                        ]),
                        startPoint: CGPoint(x: 60, y: 59),
                        endPoint: CGPoint(x: 60, y: 106)
                    )
                )
            }

            // 3. Tilted Saucer + Alien Cockpit Group
            var ufoCtx = ctx
            let tiltDegrees: Double = (mood == .blunder) ? -6.5 : (mood == .mistake ? -3.0 : 0.0)
            if tiltDegrees != 0 {
                ufoCtx.translateBy(x: 60, y: 48)
                ufoCtx.rotate(by: .degrees(tiltDegrees))
                ufoCtx.translateBy(x: -60, y: -48)
            }

            // Saucer underside hub + emitter lens
            let underHub = Path(ellipseIn: CGRect(x: 34, y: 53, width: 52, height: 14))
            ufoCtx.fill(underHub, with: .color(Color(hex: 0x0B1220).opacity(0.88)))
            let emitterLens = Path(ellipseIn: CGRect(x: 47, y: 58.5, width: 26, height: 6.5))
            ufoCtx.fill(emitterLens, with: .color(mood.accentColor.opacity(0.92)))

            // Main saucer hull disc
            let hullRect = CGRect(x: 16, y: 42, width: 88, height: 22)
            let hullPath = Path(ellipseIn: hullRect)
            ufoCtx.fill(
                hullPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.88),
                        mood.accentColor,
                        mood.saucerDark,
                    ]),
                    startPoint: CGPoint(x: 60, y: 41),
                    endPoint: CGPoint(x: 60, y: 65)
                )
            )
            ufoCtx.stroke(hullPath, with: .color(Color.white.opacity(0.45)), lineWidth: 1.2)

            // Recessed cockpit deck ring
            let deckPath = Path(ellipseIn: CGRect(x: 29, y: 44, width: 62, height: 13))
            ufoCtx.fill(deckPath, with: .color(Color(hex: 0x070B14).opacity(0.68)))

            // Glowing porthole lights along saucer rim
            let lightPoints: [(CGFloat, CGFloat)] = [
                (26, 54.0), (37, 56.8), (48.5, 58.4), (60, 59.0),
                (71.5, 58.4), (83, 56.8), (94, 54.0),
            ]
            for (lx, ly) in lightPoints {
                ufoCtx.fill(
                    Path(ellipseIn: CGRect(x: lx - 4.0, y: ly - 4.0, width: 8.0, height: 8.0)),
                    with: .color(mood.portholeColor.opacity(0.32))
                )
                ufoCtx.fill(
                    Path(ellipseIn: CGRect(x: lx - 2.1, y: ly - 2.1, width: 4.2, height: 4.2)),
                    with: .color(mood.portholeColor)
                )
            }

            // Glass dome back layer
            var dome = Path()
            dome.move(to: CGPoint(x: 35, y: 50))
            dome.addQuadCurve(to: CGPoint(x: 60, y: 17), control: CGPoint(x: 36, y: 19))
            dome.addQuadCurve(to: CGPoint(x: 85, y: 50), control: CGPoint(x: 84, y: 19))
            dome.addQuadCurve(to: CGPoint(x: 35, y: 50), control: CGPoint(x: 60, y: 55))
            dome.closeSubpath()

            ufoCtx.fill(
                dome,
                with: .linearGradient(
                    Gradient(colors: [
                        mood.accentColor.opacity(0.28),
                        Color(hex: 0x070B14).opacity(0.55),
                    ]),
                    startPoint: CGPoint(x: 60, y: 17),
                    endPoint: CGPoint(x: 60, y: 52)
                )
            )

            // Alien shoulders peeking out of cockpit
            let shoulders = Path(ellipseIn: CGRect(x: 45, y: 44, width: 30, height: 11))
            ufoCtx.fill(shoulders, with: .color(mood.alienDark.opacity(0.95)))

            // Alien Antennae
            var leftAnt = Path()
            leftAnt.move(to: CGPoint(x: 51, y: 31))
            leftAnt.addQuadCurve(to: CGPoint(x: 45.5, y: 22.5), control: CGPoint(x: 47, y: 27))
            ufoCtx.stroke(leftAnt, with: .color(mood.alienDark), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))

            var rightAnt = Path()
            rightAnt.move(to: CGPoint(x: 69, y: 31))
            rightAnt.addQuadCurve(to: CGPoint(x: 74.5, y: 22.5), control: CGPoint(x: 73, y: 27))
            ufoCtx.stroke(rightAnt, with: .color(mood.alienDark), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))

            // Antenna glowing orbs
            for (ax, ay) in [(45.2, 21.8), (74.8, 21.8)] {
                ufoCtx.fill(
                    Path(ellipseIn: CGRect(x: ax - 4.4, y: ay - 4.4, width: 8.8, height: 8.8)),
                    with: .color(mood.portholeColor.opacity(0.35))
                )
                ufoCtx.fill(
                    Path(ellipseIn: CGRect(x: ax - 2.6, y: ay - 2.6, width: 5.2, height: 5.2)),
                    with: .color(mood.portholeColor)
                )
            }

            // Alien Head
            let headRect = CGRect(x: 44.5, y: 26.5, width: 31, height: 24.5)
            let headPath = Path(ellipseIn: headRect)
            ufoCtx.fill(
                headPath,
                with: .linearGradient(
                    Gradient(colors: [mood.alienLight, mood.alienDark]),
                    startPoint: CGPoint(x: 54, y: 26),
                    endPoint: CGPoint(x: 66, y: 51)
                )
            )
            ufoCtx.stroke(headPath, with: .color(Color(hex: 0x052E16).opacity(0.32)), lineWidth: 1.0)

            // Alien Eyes & Expression
            drawExpression(in: &ufoCtx)

            // Glass dome specular highlight + luminous rim stroke (drawn over alien so it sits inside glass!)
            var gloss = Path()
            gloss.move(to: CGPoint(x: 41, y: 40))
            gloss.addQuadCurve(to: CGPoint(x: 54, y: 22), control: CGPoint(x: 42, y: 26))
            ufoCtx.stroke(
                gloss,
                with: .color(Color.white.opacity(0.45)),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
            )
            ufoCtx.stroke(dome, with: .color(mood.accentColor.opacity(0.85)), lineWidth: 1.6)

            // 4. Floating Cosmic Sparkles around the UFO
            let sparkleColor = (mood == .blunder) ? Color(hex: 0xFDA4AF) : Color(hex: 0x67E8F9)
            drawFourPointStar(in: &ctx, center: CGPoint(x: 14, y: 29), radius: 6.5, color: sparkleColor)
            drawFourPointStar(in: &ctx, center: CGPoint(x: 106, y: 22), radius: 5.5, color: mood.portholeColor)
            drawFourPointStar(in: &ctx, center: CGPoint(x: 103, y: 69), radius: 3.8, color: sparkleColor.opacity(0.85))
            ctx.fill(
                Path(ellipseIn: CGRect(x: 18, y: 64, width: 3.6, height: 3.6)),
                with: .color(mood.portholeColor.opacity(0.85))
            )
            if mood == .brilliant {
                drawFourPointStar(in: &ctx, center: CGPoint(x: 60, y: 8.5), radius: 4.5, color: Color(hex: 0xFDE047))
            }
        }
        .frame(width: size, height: size * (112.0 / 120.0))
        .accessibilityHidden(true)
    }

    private func drawExpression(in ctx: inout GraphicsContext) {
        switch mood {
        case .brilliant, .best:
            // Glossy classic alien eyes with twin starlight catchlights
            for (ex, tilt) in [(54.0, -10.0), (66.0, 10.0)] {
                var eyeCtx = ctx
                eyeCtx.translateBy(x: ex, y: 38.2)
                eyeCtx.rotate(by: .degrees(tilt))
                eyeCtx.fill(
                    Path(ellipseIn: CGRect(x: -4.0, y: -5.2, width: 8.0, height: 10.4)),
                    with: .color(Color(hex: 0x071018))
                )
                eyeCtx.fill(
                    Path(ellipseIn: CGRect(x: -2.2, y: -3.2, width: 2.6, height: 2.6)),
                    with: .color(Color(hex: 0xE0F2FE))
                )
                eyeCtx.fill(
                    Path(ellipseIn: CGRect(x: 0.6, y: 0.8, width: 1.4, height: 1.4)),
                    with: .color(Color(hex: 0x67E8F9).opacity(0.85))
                )
            }
            // Big joyful smile
            var smile = Path()
            smile.move(to: CGPoint(x: 53.5, y: 44.8))
            smile.addQuadCurve(to: CGPoint(x: 66.5, y: 44.8), control: CGPoint(x: 60, y: 49.6))
            ctx.stroke(smile, with: .color(Color(hex: 0x052E16)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))

        case .great:
            // Cool futuristic cyan visor + confident smirk
            let visor = Path(roundedRect: CGRect(x: 48.0, y: 34.0, width: 24.0, height: 7.4), cornerRadius: 3.7)
            ctx.fill(
                visor,
                with: .linearGradient(
                    Gradient(colors: [Color(hex: 0x0EA5E9), Color(hex: 0x071018), Color(hex: 0x38BDF8)]),
                    startPoint: CGPoint(x: 48, y: 34),
                    endPoint: CGPoint(x: 72, y: 42)
                )
            )
            ctx.stroke(visor, with: .color(Color(hex: 0x7DD3FC)), lineWidth: 1.1)
            var glint = Path()
            glint.move(to: CGPoint(x: 51, y: 36.2))
            glint.addLine(to: CGPoint(x: 58, y: 36.2))
            ctx.stroke(glint, with: .color(Color.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

            var smirk = Path()
            smirk.move(to: CGPoint(x: 54.5, y: 45.2))
            smirk.addQuadCurve(to: CGPoint(x: 66.0, y: 44.2), control: CGPoint(x: 61, y: 48.5))
            ctx.stroke(smirk, with: .color(Color(hex: 0x052E16)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))

        case .book:
            // Cute scholar glasses over bright eyes
            for ex in [54.0, 66.0] {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: ex - 3.2, y: 34.4, width: 6.4, height: 7.2)),
                    with: .color(Color(hex: 0x071018))
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: ex - 1.8, y: 35.8, width: 2.0, height: 2.0)),
                    with: .color(Color.white)
                )
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: ex - 4.7, y: 33.4, width: 9.4, height: 9.4)),
                    with: .color(Color(hex: 0xFEF3C7)),
                    lineWidth: 1.3
                )
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 58.7, y: 38))
            bridge.addLine(to: CGPoint(x: 61.3, y: 38))
            ctx.stroke(bridge, with: .color(Color(hex: 0xFEF3C7)), lineWidth: 1.3)

            var smile = Path()
            smile.move(to: CGPoint(x: 55.5, y: 45.4))
            smile.addQuadCurve(to: CGPoint(x: 64.5, y: 45.4), control: CGPoint(x: 60, y: 48.2))
            ctx.stroke(smile, with: .color(Color(hex: 0x451A03)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

        case .mistake:
            // Surprised wide eyes + small "o" mouth
            for ex in [54.0, 66.0] {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: ex - 3.5, y: 34.0, width: 7.0, height: 7.8)),
                    with: .color(Color(hex: 0x071018))
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: ex - 1.6, y: 35.4, width: 2.2, height: 2.2)),
                    with: .color(Color.white)
                )
            }
            ctx.stroke(
                Path(ellipseIn: CGRect(x: 57.5, y: 43.2, width: 5.0, height: 5.2)),
                with: .color(Color(hex: 0x071018)),
                lineWidth: 1.8
            )
            drawSweatDrop(in: &ctx, at: CGPoint(x: 74.5, y: 35.0))

        case .blunder:
            // Classic X-X dizzy eyes + frown + blue sweat drop
            var xEyes = Path()
            xEyes.move(to: CGPoint(x: 50.5, y: 34.8)); xEyes.addLine(to: CGPoint(x: 57.2, y: 40.5))
            xEyes.move(to: CGPoint(x: 57.2, y: 34.8)); xEyes.addLine(to: CGPoint(x: 50.5, y: 40.5))
            xEyes.move(to: CGPoint(x: 62.8, y: 34.8)); xEyes.addLine(to: CGPoint(x: 69.5, y: 40.5))
            xEyes.move(to: CGPoint(x: 69.5, y: 34.8)); xEyes.addLine(to: CGPoint(x: 62.8, y: 40.5))
            ctx.stroke(xEyes, with: .color(Color(hex: 0x071018)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            var frown = Path()
            frown.move(to: CGPoint(x: 54.5, y: 46.8))
            frown.addQuadCurve(to: CGPoint(x: 65.5, y: 46.8), control: CGPoint(x: 60, y: 42.6))
            ctx.stroke(frown, with: .color(Color(hex: 0x071018)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))

            drawSweatDrop(in: &ctx, at: CGPoint(x: 75.0, y: 36.5))
        }
    }

    private func drawSweatDrop(in ctx: inout GraphicsContext, at pt: CGPoint) {
        var drop = Path()
        drop.move(to: pt)
        drop.addQuadCurve(to: CGPoint(x: pt.x - 2.6, y: pt.y + 5.2), control: CGPoint(x: pt.x - 3.2, y: pt.y + 2.5))
        drop.addQuadCurve(to: CGPoint(x: pt.x + 2.6, y: pt.y + 5.2), control: CGPoint(x: pt.x, y: pt.y + 8.0))
        drop.addQuadCurve(to: pt, control: CGPoint(x: pt.x + 3.2, y: pt.y + 2.5))
        drop.closeSubpath()
        ctx.fill(drop, with: .color(Color(hex: 0x93C5FD)))
    }

    private func drawFourPointStar(in ctx: inout GraphicsContext, center: CGPoint, radius r: CGFloat, color: Color) {
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
