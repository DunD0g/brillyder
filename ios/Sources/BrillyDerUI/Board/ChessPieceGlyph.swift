import SwiftUI
import BrillyDerCore

/// 100% original, zero-GPL, tournament-grade Neo-Staunton vector chess pieces rendered in SwiftUI Canvas.
/// Sculpted high-contrast silhouettes with unified layer shadows, crisp Black-piece rim contrast for dark/Neon
/// squares, and responsive detail culling for mini-boards.
public struct ChessPieceView: View {
    let piece: Piece
    let squareSize: CGFloat

    public init(piece: Piece, squareSize: CGFloat) {
        self.piece = piece
        self.squareSize = squareSize
    }

    public var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            guard s > 2 else { return }
            let isWhite = piece.color == .white
            let showDetails = s >= 16

            let fillGrad = isWhite
                ? GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xE2E8F0), Color(hex: 0xCBD5E1)]),
                    startPoint: CGPoint(x: s * 0.25, y: s * 0.10),
                    endPoint: CGPoint(x: s * 0.80, y: s * 0.92)
                )
                : GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Color(hex: 0x475569), Color(hex: 0x1E293B), Color(hex: 0x090E1A)]),
                    startPoint: CGPoint(x: s * 0.22, y: s * 0.10),
                    endPoint: CGPoint(x: s * 0.82, y: s * 0.92)
                )

            let outlineColor = isWhite ? Color(hex: 0x0F172A) : Color(hex: 0x020617)
            let haloColor: Color? = isWhite ? nil : Color(hex: 0xCBD5E1).opacity(s >= 24 ? 0.52 : 0.35)
            let detailColor = isWhite ? Color(hex: 0x1E293B).opacity(0.85) : Color(hex: 0xE2E8F0).opacity(0.76)
            let rimColor = isWhite ? Color.white.opacity(0.88) : Color(hex: 0xCBD5E1).opacity(0.32)
            let strokeW = max(0.35, s * 0.038)
            let detailW = max(0.35, s * 0.026)

            // Single grounded shadow via drawLayer (avoids per-subshape filter artifacts & saves GPU time)
            var shadowCtx = ctx
            shadowCtx.addFilter(.shadow(
                color: Color.black.opacity(isWhite ? 0.30 : 0.40),
                radius: max(0.6, s * 0.035),
                y: max(0.4, s * 0.025)
            ))

            shadowCtx.drawLayer { layer in
                switch piece.type {
                case .pawn:
                    drawPawn(ctx: &layer, s: s, fill: fillGrad, outline: outlineColor, halo: haloColor, detail: detailColor, rim: rimColor, strokeW: strokeW, detailW: detailW, showDetails: showDetails)
                case .rook:
                    drawRook(ctx: &layer, s: s, fill: fillGrad, outline: outlineColor, halo: haloColor, detail: detailColor, strokeW: strokeW, detailW: detailW, showDetails: showDetails)
                case .knight:
                    drawKnight(ctx: &layer, s: s, fill: fillGrad, outline: outlineColor, halo: haloColor, detail: detailColor, strokeW: strokeW, detailW: detailW, isWhite: isWhite, showDetails: showDetails)
                case .bishop:
                    drawBishop(ctx: &layer, s: s, fill: fillGrad, outline: outlineColor, halo: haloColor, detail: detailColor, strokeW: strokeW, detailW: detailW, showDetails: showDetails)
                case .queen:
                    drawQueen(ctx: &layer, s: s, fill: fillGrad, outline: outlineColor, halo: haloColor, detail: detailColor, strokeW: strokeW, detailW: detailW, showDetails: showDetails)
                case .king:
                    drawKing(ctx: &layer, s: s, fill: fillGrad, outline: outlineColor, halo: haloColor, detail: detailColor, strokeW: strokeW, detailW: detailW, showDetails: showDetails)
                }
            }
        }
        .frame(width: squareSize, height: squareSize)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Helpers (Normalized 0...100 space)

    private func pt(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {
        CGPoint(x: x / 100.0 * s, y: y / 100.0 * s)
    }

    private func strokeStyle(_ w: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
    }

    private func paintShapes(
        _ shapes: [Path],
        in ctx: inout GraphicsContext,
        fill: GraphicsContext.Shading,
        outline: Color,
        halo: Color?,
        strokeW: CGFloat
    ) {
        // Soft outer luminous halo for Black pieces so they pop cleanly on Neon & dark squares
        if let halo {
            for shape in shapes {
                ctx.stroke(shape, with: .color(halo), style: strokeStyle(strokeW * 1.65))
            }
        }
        for shape in shapes {
            ctx.fill(shape, with: fill)
            ctx.stroke(shape, with: .color(outline), style: strokeStyle(strokeW))
        }
    }

    // MARK: - 1. Pawn (Classic shorter Staunton silhouette)
    private func drawPawn(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, halo: Color?, detail: Color, rim: Color,
        strokeW: CGFloat, detailW: CGFloat, showDetails: Bool
    ) {
        var body = Path()
        body.move(to: pt(25, 88, s))
        body.addQuadCurve(to: pt(35, 74, s), control: pt(25, 78, s))
        body.addCurve(to: pt(41, 52, s), control1: pt(39, 67, s), control2: pt(42, 58, s))
        body.addLine(to: pt(59, 52, s))
        body.addCurve(to: pt(65, 74, s), control1: pt(58, 58, s), control2: pt(61, 67, s))
        body.addQuadCurve(to: pt(75, 88, s), control: pt(75, 78, s))
        body.closeSubpath()

        let collar = Path(roundedRect: CGRect(x: 0.35 * s, y: 0.47 * s, width: 0.30 * s, height: 0.075 * s), cornerRadius: 0.038 * s)
        let headRect = CGRect(x: 0.355 * s, y: 0.23 * s, width: 0.29 * s, height: 0.275 * s)
        let head = Path(ellipseIn: headRect)
        let base = Path(roundedRect: CGRect(x: 0.22 * s, y: 0.83 * s, width: 0.56 * s, height: 0.08 * s), cornerRadius: 0.03 * s)

        paintShapes([body, collar, head, base], in: &ctx, fill: fill, outline: outline, halo: halo, strokeW: strokeW)

        if showDetails {
            var line = Path()
            line.move(to: pt(31, 78, s)); line.addLine(to: pt(69, 78, s))
            ctx.stroke(line, with: .color(detail), style: strokeStyle(detailW))
            ctx.stroke(Path(ellipseIn: headRect.insetBy(dx: s * 0.032, dy: s * 0.032)), with: .color(rim.opacity(0.35)), lineWidth: max(0.5, s * 0.016))
        }
    }

    // MARK: - 2. Rook
    private func drawRook(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, halo: Color?, detail: Color,
        strokeW: CGFloat, detailW: CGFloat, showDetails: Bool
    ) {
        var silhouette = Path()
        silhouette.move(to: pt(23, 16, s))
        silhouette.addLine(to: pt(35, 16, s))
        silhouette.addLine(to: pt(35, 25, s))
        silhouette.addLine(to: pt(44, 25, s))
        silhouette.addLine(to: pt(44, 16, s))
        silhouette.addLine(to: pt(56, 16, s))
        silhouette.addLine(to: pt(56, 25, s))
        silhouette.addLine(to: pt(65, 25, s))
        silhouette.addLine(to: pt(65, 16, s))
        silhouette.addLine(to: pt(77, 16, s))
        silhouette.addLine(to: pt(77, 34, s))
        silhouette.addLine(to: pt(69, 41, s))
        silhouette.addLine(to: pt(67, 72, s))
        silhouette.addLine(to: pt(76, 79, s))
        silhouette.addLine(to: pt(76, 84, s))
        silhouette.addLine(to: pt(24, 84, s))
        silhouette.addLine(to: pt(24, 79, s))
        silhouette.addLine(to: pt(33, 72, s))
        silhouette.addLine(to: pt(31, 41, s))
        silhouette.addLine(to: pt(23, 34, s))
        silhouette.closeSubpath()

        let base = Path(roundedRect: CGRect(x: 0.19 * s, y: 0.82 * s, width: 0.62 * s, height: 0.09 * s), cornerRadius: 0.03 * s)

        paintShapes([silhouette, base], in: &ctx, fill: fill, outline: outline, halo: halo, strokeW: strokeW)

        if showDetails {
            var bands = Path()
            bands.move(to: pt(24, 34, s)); bands.addLine(to: pt(76, 34, s))
            bands.move(to: pt(31, 41, s)); bands.addLine(to: pt(69, 41, s))
            bands.move(to: pt(33, 72, s)); bands.addLine(to: pt(67, 72, s))
            ctx.stroke(bands, with: .color(detail), style: strokeStyle(detailW))
        }
    }

    // MARK: - 3. Knight (Sleek throat/jaw silhouette)
    private func drawKnight(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, halo: Color?, detail: Color,
        strokeW: CGFloat, detailW: CGFloat, isWhite: Bool, showDetails: Bool
    ) {
        var horse = Path()
        horse.move(to: pt(25, 83, s))
        horse.addCurve(to: pt(43, 55, s), control1: pt(26, 69, s), control2: pt(36, 63, s))
        // Clean tucked jaw into muzzle
        horse.addCurve(to: pt(20, 49, s), control1: pt(37, 52, s), control2: pt(26, 54, s))
        horse.addCurve(to: pt(24, 36, s), control1: pt(17, 44, s), control2: pt(20, 39, s))
        horse.addLine(to: pt(35, 25, s))
        horse.addLine(to: pt(39, 14, s))
        horse.addLine(to: pt(47, 21, s))
        horse.addLine(to: pt(55, 14, s))
        horse.addLine(to: pt(57, 23, s))
        horse.addCurve(to: pt(78, 52, s), control1: pt(71, 27, s), control2: pt(79, 39, s))
        horse.addCurve(to: pt(75, 83, s), control1: pt(79, 65, s), control2: pt(77, 75, s))
        horse.closeSubpath()

        let base = Path(roundedRect: CGRect(x: 0.19 * s, y: 0.81 * s, width: 0.62 * s, height: 0.10 * s), cornerRadius: 0.035 * s)

        paintShapes([horse, base], in: &ctx, fill: fill, outline: outline, halo: halo, strokeW: strokeW)

        if showDetails {
            let eye = Path(ellipseIn: CGRect(x: 0.34 * s, y: 0.305 * s, width: 0.056 * s, height: 0.056 * s))
            ctx.fill(eye, with: .color(isWhite ? Color(hex: 0x0F172A) : Color(hex: 0xF1F5F9)))

            let nostril = Path(ellipseIn: CGRect(x: 0.225 * s, y: 0.44 * s, width: 0.035 * s, height: 0.035 * s))
            ctx.fill(nostril, with: .color(detail))

            var mane = Path()
            mane.move(to: pt(57, 27, s))
            mane.addCurve(to: pt(68, 74, s), control1: pt(68, 35, s), control2: pt(71, 56, s))
            ctx.stroke(mane, with: .color(detail), style: strokeStyle(detailW))
        }
    }

    // MARK: - 4. Bishop (Overlapped mitre/orb + classic diagonal slash)
    private func drawBishop(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, halo: Color?, detail: Color,
        strokeW: CGFloat, detailW: CGFloat, showDetails: Bool
    ) {
        let orb = Path(ellipseIn: CGRect(x: 0.44 * s, y: 0.11 * s, width: 0.12 * s, height: 0.12 * s))

        var mitre = Path()
        mitre.move(to: pt(50, 20, s))
        mitre.addCurve(to: pt(68, 49, s), control1: pt(64, 26, s), control2: pt(71, 38, s))
        mitre.addCurve(to: pt(61, 66, s), control1: pt(66, 57, s), control2: pt(62, 62, s))
        mitre.addLine(to: pt(69, 78, s))
        mitre.addLine(to: pt(31, 78, s))
        mitre.addLine(to: pt(39, 66, s))
        mitre.addCurve(to: pt(32, 49, s), control1: pt(38, 62, s), control2: pt(34, 57, s))
        mitre.addCurve(to: pt(50, 20, s), control1: pt(29, 38, s), control2: pt(36, 26, s))
        mitre.closeSubpath()

        let base = Path(roundedRect: CGRect(x: 0.20 * s, y: 0.78 * s, width: 0.60 * s, height: 0.12 * s), cornerRadius: 0.045 * s)

        paintShapes([orb, mitre, base], in: &ctx, fill: fill, outline: outline, halo: halo, strokeW: strokeW)

        if showDetails {
            var lines = Path()
            // Classic Staunton diagonal mitre cut + cross + collar bands
            lines.move(to: pt(58, 30, s)); lines.addLine(to: pt(47, 45, s))
            lines.move(to: pt(50, 38, s)); lines.addLine(to: pt(50, 52, s))
            lines.move(to: pt(44, 45, s)); lines.addLine(to: pt(56, 45, s))
            lines.move(to: pt(37, 65, s)); lines.addLine(to: pt(63, 65, s))
            lines.move(to: pt(25, 84, s)); lines.addLine(to: pt(75, 84, s))
            ctx.stroke(lines, with: .color(detail), style: strokeStyle(detailW))
        }
    }

    // MARK: - 5. Queen
    private func drawQueen(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, halo: Color?, detail: Color,
        strokeW: CGFloat, detailW: CGFloat, showDetails: Bool
    ) {
        var crown = Path()
        crown.move(to: pt(23, 77, s))
        crown.addLine(to: pt(15, 31, s))
        crown.addLine(to: pt(31, 52, s))
        crown.addLine(to: pt(34, 24, s))
        crown.addLine(to: pt(45, 48, s))
        crown.addLine(to: pt(50, 20, s))
        crown.addLine(to: pt(55, 48, s))
        crown.addLine(to: pt(66, 24, s))
        crown.addLine(to: pt(69, 52, s))
        crown.addLine(to: pt(85, 31, s))
        crown.addLine(to: pt(77, 77, s))
        crown.closeSubpath()

        let base = Path(roundedRect: CGRect(x: 0.20 * s, y: 0.76 * s, width: 0.60 * s, height: 0.14 * s), cornerRadius: 0.045 * s)

        var pearls: [Path] = []
        let pearlCenters: [(CGFloat, CGFloat)] = [(15, 28), (34, 21), (50, 17), (66, 21), (85, 28)]
        let r = s * 0.045
        for (px, py) in pearlCenters {
            let c = pt(px, py, s)
            pearls.append(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)))
        }

        paintShapes([crown, base] + pearls, in: &ctx, fill: fill, outline: outline, halo: halo, strokeW: strokeW)

        if showDetails {
            var bands = Path()
            bands.move(to: pt(24, 68, s)); bands.addQuadCurve(to: pt(76, 68, s), control: pt(50, 62, s))
            bands.move(to: pt(24, 83, s)); bands.addLine(to: pt(76, 83, s))
            ctx.stroke(bands, with: .color(detail), style: strokeStyle(detailW))
        }
    }

    // MARK: - 6. King (Unified 12-point seamless royal cross)
    private func drawKing(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, halo: Color?, detail: Color,
        strokeW: CGFloat, detailW: CGFloat, showDetails: Bool
    ) {
        // Unified 12-point '+' cross polygon (zero internal seam lines)
        var cross = Path()
        cross.move(to: pt(46.5, 9, s))
        cross.addLine(to: pt(53.5, 9, s))
        cross.addLine(to: pt(53.5, 14.5, s))
        cross.addLine(to: pt(61, 14.5, s))
        cross.addLine(to: pt(61, 21, s))
        cross.addLine(to: pt(53.5, 21, s))
        cross.addLine(to: pt(53.5, 32, s))
        cross.addLine(to: pt(46.5, 32, s))
        cross.addLine(to: pt(46.5, 21, s))
        cross.addLine(to: pt(39, 21, s))
        cross.addLine(to: pt(39, 14.5, s))
        cross.addLine(to: pt(46.5, 14.5, s))
        cross.closeSubpath()

        var body = Path()
        body.move(to: pt(25, 77, s))
        body.addCurve(to: pt(16, 46, s), control1: pt(19, 64, s), control2: pt(14, 54, s))
        body.addCurve(to: pt(45, 34, s), control1: pt(19, 32, s), control2: pt(36, 30, s))
        body.addLine(to: pt(50, 31, s))
        body.addLine(to: pt(55, 34, s))
        body.addCurve(to: pt(84, 46, s), control1: pt(64, 30, s), control2: pt(81, 32, s))
        body.addCurve(to: pt(75, 77, s), control1: pt(86, 54, s), control2: pt(81, 64, s))
        body.closeSubpath()

        let base = Path(roundedRect: CGRect(x: 0.20 * s, y: 0.76 * s, width: 0.60 * s, height: 0.14 * s), cornerRadius: 0.045 * s)

        paintShapes([cross, body, base], in: &ctx, fill: fill, outline: outline, halo: halo, strokeW: strokeW)

        if showDetails {
            var details = Path()
            details.move(to: pt(50, 34, s)); details.addLine(to: pt(50, 68, s))
            details.move(to: pt(25, 68, s)); details.addQuadCurve(to: pt(75, 68, s), control: pt(50, 62, s))
            details.move(to: pt(24, 83, s)); details.addLine(to: pt(76, 83, s))
            ctx.stroke(details, with: .color(detail), style: strokeStyle(detailW))
        }
    }
}
