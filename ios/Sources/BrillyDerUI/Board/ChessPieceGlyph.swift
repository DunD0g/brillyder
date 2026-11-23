import SwiftUI
import BrillyDerCore

/// 100% original, zero-GPL, tournament-grade Neo-Staunton vector chess pieces rendered in SwiftUI Canvas.
/// Replaces skinny/misaligned system Unicode glyphs with bold, sculpted high-contrast silhouettes filling ~86% of each square.
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
            let isWhite = piece.color == .white

            let fillGrad = isWhite
                ? GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xE2E8F0), Color(hex: 0xCBD5E1)]),
                    startPoint: CGPoint(x: s * 0.25, y: s * 0.10),
                    endPoint: CGPoint(x: s * 0.80, y: s * 0.92)
                )
                : GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Color(hex: 0x334155), Color(hex: 0x111827), Color(hex: 0x030712)]),
                    startPoint: CGPoint(x: s * 0.22, y: s * 0.10),
                    endPoint: CGPoint(x: s * 0.82, y: s * 0.92)
                )

            let outlineColor = isWhite ? Color(hex: 0x0F172A) : Color(hex: 0x020617)
            let detailColor = isWhite ? Color(hex: 0x1E293B).opacity(0.85) : Color(hex: 0xCBD5E1).opacity(0.72)
            let rimColor = isWhite ? Color.white.opacity(0.9) : Color.white.opacity(0.28)
            let strokeW = max(1.15, s * 0.042)
            let detailW = max(0.95, s * 0.030)

            // Soft grounded shadow
            var shadowCtx = ctx
            shadowCtx.addFilter(.shadow(color: Color.black.opacity(isWhite ? 0.32 : 0.42), radius: max(1.2, s * 0.04), y: max(0.8, s * 0.03)))

            switch piece.type {
            case .pawn:
                drawPawn(ctx: &shadowCtx, s: s, fill: fillGrad, outline: outlineColor, detail: detailColor, rim: rimColor, strokeW: strokeW, detailW: detailW)
            case .rook:
                drawRook(ctx: &shadowCtx, s: s, fill: fillGrad, outline: outlineColor, detail: detailColor, rim: rimColor, strokeW: strokeW, detailW: detailW)
            case .knight:
                drawKnight(ctx: &shadowCtx, s: s, fill: fillGrad, outline: outlineColor, detail: detailColor, rim: rimColor, strokeW: strokeW, detailW: detailW, isWhite: isWhite)
            case .bishop:
                drawBishop(ctx: &shadowCtx, s: s, fill: fillGrad, outline: outlineColor, detail: detailColor, rim: rimColor, strokeW: strokeW, detailW: detailW)
            case .queen:
                drawQueen(ctx: &shadowCtx, s: s, fill: fillGrad, outline: outlineColor, detail: detailColor, rim: rimColor, strokeW: strokeW, detailW: detailW)
            case .king:
                drawKing(ctx: &shadowCtx, s: s, fill: fillGrad, outline: outlineColor, detail: detailColor, rim: rimColor, strokeW: strokeW, detailW: detailW)
            }
        }
        .frame(width: squareSize, height: squareSize)
        .allowsHitTesting(false)
    }

    // MARK: - Helper Coordinate Scaling (Normalized 0...100 space)

    private func pt(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {
        CGPoint(x: x / 100.0 * s, y: y / 100.0 * s)
    }

    private func strokeStyle(_ w: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
    }

    // MARK: - 1. Pawn
    private func drawPawn(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, detail: Color, rim: Color,
        strokeW: CGFloat, detailW: CGFloat
    ) {
        // Pedestal + torso
        var body = Path()
        body.move(to: pt(24, 88, s))
        body.addQuadCurve(to: pt(35, 72, s), control: pt(24, 76, s))
        body.addCurve(to: pt(41, 46, s), control1: pt(39, 64, s), control2: pt(42, 54, s))
        body.addLine(to: pt(59, 46, s))
        body.addCurve(to: pt(65, 72, s), control1: pt(58, 54, s), control2: pt(61, 64, s))
        body.addQuadCurve(to: pt(76, 88, s), control: pt(76, 76, s))
        body.closeSubpath()

        // Collar ring
        let collar = Path(roundedRect: CGRect(x: 0.34 * s, y: 0.42 * s, width: 0.32 * s, height: 0.08 * s), cornerRadius: 0.04 * s)
        // Spherical head
        let headRect = CGRect(x: 0.34 * s, y: 0.16 * s, width: 0.32 * s, height: 0.30 * s)
        let head = Path(ellipseIn: headRect)
        // Base bar
        let base = Path(roundedRect: CGRect(x: 0.21 * s, y: 0.83 * s, width: 0.58 * s, height: 0.08 * s), cornerRadius: 0.03 * s)

        for shape in [body, collar, head, base] {
            ctx.fill(shape, with: fill)
            ctx.stroke(shape, with: .color(outline), style: strokeStyle(strokeW))
        }

        // Specular & collar line
        var line = Path()
        line.move(to: pt(30, 77, s)); line.addLine(to: pt(70, 77, s))
        ctx.stroke(line, with: .color(detail), style: strokeStyle(detailW))
        ctx.stroke(Path(ellipseIn: headRect.insetBy(dx: s * 0.03, dy: s * 0.03)), with: .color(rim.opacity(0.35)), lineWidth: max(0.6, s * 0.018))
    }

    // MARK: - 2. Rook
    private func drawRook(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, detail: Color, rim: Color,
        strokeW: CGFloat, detailW: CGFloat
    ) {
        var silhouette = Path()
        // Battlements (3 merlons)
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
        // Tower shaft
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

        ctx.fill(silhouette, with: fill)
        ctx.stroke(silhouette, with: .color(outline), style: strokeStyle(strokeW))
        ctx.fill(base, with: fill)
        ctx.stroke(base, with: .color(outline), style: strokeStyle(strokeW))

        var bands = Path()
        bands.move(to: pt(27, 35, s)); bands.addLine(to: pt(73, 35, s))
        bands.move(to: pt(32, 42, s)); bands.addLine(to: pt(68, 42, s))
        bands.move(to: pt(33, 72, s)); bands.addLine(to: pt(67, 72, s))
        ctx.stroke(bands, with: .color(detail), style: strokeStyle(detailW))
        _ = rim
    }

    // MARK: - 3. Knight
    private func drawKnight(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, detail: Color, rim: Color,
        strokeW: CGFloat, detailW: CGFloat, isWhite: Bool
    ) {
        var horse = Path()
        horse.move(to: pt(25, 83, s))
        // Chest curving up to jaw & muzzle
        horse.addCurve(to: pt(43, 56, s), control1: pt(26, 70, s), control2: pt(36, 64, s))
        horse.addQuadCurve(to: pt(32, 55, s), control: pt(37, 58, s))
        // Lower lip -> muzzle -> nose bridge
        horse.addCurve(to: pt(19, 49, s), control1: pt(24, 56, s), control2: pt(18, 53, s))
        horse.addCurve(to: pt(24, 37, s), control1: pt(17, 44, s), control2: pt(20, 40, s))
        horse.addLine(to: pt(35, 25, s))
        // Ears & crown
        horse.addLine(to: pt(39, 14, s))
        horse.addLine(to: pt(47, 21, s))
        horse.addLine(to: pt(55, 14, s))
        horse.addLine(to: pt(57, 23, s))
        // Sweeping mane down the back
        horse.addCurve(to: pt(78, 52, s), control1: pt(71, 27, s), control2: pt(79, 39, s))
        horse.addCurve(to: pt(75, 83, s), control1: pt(79, 65, s), control2: pt(77, 75, s))
        horse.closeSubpath()

        let base = Path(roundedRect: CGRect(x: 0.19 * s, y: 0.81 * s, width: 0.62 * s, height: 0.10 * s), cornerRadius: 0.035 * s)

        ctx.fill(horse, with: fill)
        ctx.stroke(horse, with: .color(outline), style: strokeStyle(strokeW))
        ctx.fill(base, with: fill)
        ctx.stroke(base, with: .color(outline), style: strokeStyle(strokeW))

        // Sculpted eye, nostril & flowing mane crease
        let eye = Path(ellipseIn: CGRect(x: 0.34 * s, y: 0.31 * s, width: 0.058 * s, height: 0.058 * s))
        ctx.fill(eye, with: .color(isWhite ? Color(hex: 0x0F172A) : Color(hex: 0xE2E8F0)))

        let nostril = Path(ellipseIn: CGRect(x: 0.225 * s, y: 0.445 * s, width: 0.036 * s, height: 0.036 * s))
        ctx.fill(nostril, with: .color(detail))

        var mane = Path()
        mane.move(to: pt(57, 27, s))
        mane.addCurve(to: pt(68, 74, s), control1: pt(68, 35, s), control2: pt(71, 56, s))
        ctx.stroke(mane, with: .color(detail), style: strokeStyle(detailW))
        _ = rim
    }

    // MARK: - 4. Bishop
    private func drawBishop(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, detail: Color, rim: Color,
        strokeW: CGFloat, detailW: CGFloat
    ) {
        // Finial orb
        let orb = Path(ellipseIn: CGRect(x: 0.44 * s, y: 0.10 * s, width: 0.12 * s, height: 0.12 * s))

        // Mitre dome + neck + skirt
        var mitre = Path()
        mitre.move(to: pt(50, 21, s))
        mitre.addCurve(to: pt(68, 49, s), control1: pt(64, 27, s), control2: pt(71, 38, s))
        mitre.addCurve(to: pt(61, 66, s), control1: pt(66, 57, s), control2: pt(62, 62, s))
        mitre.addLine(to: pt(69, 77, s))
        mitre.addLine(to: pt(31, 77, s))
        mitre.addLine(to: pt(39, 66, s))
        mitre.addCurve(to: pt(32, 49, s), control1: pt(38, 62, s), control2: pt(34, 57, s))
        mitre.addCurve(to: pt(50, 21, s), control1: pt(29, 38, s), control2: pt(36, 27, s))
        mitre.closeSubpath()

        let base = Path(roundedRect: CGRect(x: 0.20 * s, y: 0.78 * s, width: 0.60 * s, height: 0.12 * s), cornerRadius: 0.045 * s)

        for shape in [orb, mitre, base] {
            ctx.fill(shape, with: fill)
            ctx.stroke(shape, with: .color(outline), style: strokeStyle(strokeW))
        }

        // Classic diagonal mitre slash + cross + collar
        var lines = Path()
        lines.move(to: pt(50, 34, s)); lines.addLine(to: pt(50, 50, s))
        lines.move(to: pt(43, 42, s)); lines.addLine(to: pt(57, 42, s))
        lines.move(to: pt(37, 64, s)); lines.addLine(to: pt(63, 64, s))
        lines.move(to: pt(28, 84, s)); lines.addLine(to: pt(72, 84, s))
        ctx.stroke(lines, with: .color(detail), style: strokeStyle(detailW))
        _ = rim
    }

    // MARK: - 5. Queen
    private func drawQueen(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, detail: Color, rim: Color,
        strokeW: CGFloat, detailW: CGFloat
    ) {
        var crown = Path()
        crown.move(to: pt(23, 76, s))
        crown.addLine(to: pt(15, 31, s))
        crown.addLine(to: pt(31, 52, s))
        crown.addLine(to: pt(34, 24, s))
        crown.addLine(to: pt(45, 48, s))
        crown.addLine(to: pt(50, 20, s))
        crown.addLine(to: pt(55, 48, s))
        crown.addLine(to: pt(66, 24, s))
        crown.addLine(to: pt(69, 52, s))
        crown.addLine(to: pt(85, 31, s))
        crown.addLine(to: pt(77, 76, s))
        crown.closeSubpath()

        let base = Path(roundedRect: CGRect(x: 0.20 * s, y: 0.76 * s, width: 0.60 * s, height: 0.14 * s), cornerRadius: 0.045 * s)

        ctx.fill(crown, with: fill)
        ctx.stroke(crown, with: .color(outline), style: strokeStyle(strokeW))
        ctx.fill(base, with: fill)
        ctx.stroke(base, with: .color(outline), style: strokeStyle(strokeW))

        // 5 crown pearls
        let pearlCenters: [(CGFloat, CGFloat)] = [(15, 28), (34, 21), (50, 17), (66, 21), (85, 28)]
        let r = s * 0.045
        for (px, py) in pearlCenters {
            let c = pt(px, py, s)
            let pearl = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(pearl, with: fill)
            ctx.stroke(pearl, with: .color(outline), style: strokeStyle(strokeW * 0.85))
        }

        var bands = Path()
        bands.move(to: pt(26, 68, s)); bands.addQuadCurve(to: pt(74, 68, s), control: pt(50, 62, s))
        bands.move(to: pt(26, 83, s)); bands.addLine(to: pt(74, 83, s))
        ctx.stroke(bands, with: .color(detail), style: strokeStyle(detailW))
        _ = rim
    }

    // MARK: - 6. King
    private func drawKing(
        ctx: inout GraphicsContext, s: CGFloat,
        fill: GraphicsContext.Shading, outline: Color, detail: Color, rim: Color,
        strokeW: CGFloat, detailW: CGFloat
    ) {
        // Bold royal cross at apex
        var cross = Path()
        cross.addRoundedRect(in: CGRect(x: 0.465 * s, y: 0.09 * s, width: 0.07 * s, height: 0.22 * s), cornerSize: CGSize(width: 0.02 * s, height: 0.02 * s))
        cross.addRoundedRect(in: CGRect(x: 0.39 * s, y: 0.145 * s, width: 0.22 * s, height: 0.065 * s), cornerSize: CGSize(width: 0.02 * s, height: 0.02 * s))

        // Sculpted twin-lobed royal crown
        var body = Path()
        body.move(to: pt(25, 76, s))
        body.addCurve(to: pt(16, 46, s), control1: pt(19, 64, s), control2: pt(14, 54, s))
        body.addCurve(to: pt(45, 34, s), control1: pt(19, 32, s), control2: pt(36, 30, s))
        body.addLine(to: pt(50, 31, s))
        body.addLine(to: pt(55, 34, s))
        body.addCurve(to: pt(84, 46, s), control1: pt(64, 30, s), control2: pt(81, 32, s))
        body.addCurve(to: pt(75, 76, s), control1: pt(86, 54, s), control2: pt(81, 64, s))
        body.closeSubpath()

        let base = Path(roundedRect: CGRect(x: 0.20 * s, y: 0.76 * s, width: 0.60 * s, height: 0.14 * s), cornerRadius: 0.045 * s)

        for shape in [cross, body, base] {
            ctx.fill(shape, with: fill)
            ctx.stroke(shape, with: .color(outline), style: strokeStyle(strokeW))
        }

        // Center spine & royal collar arcs
        var details = Path()
        details.move(to: pt(50, 34, s)); details.addLine(to: pt(50, 68, s))
        details.move(to: pt(27, 68, s)); details.addQuadCurve(to: pt(73, 68, s), control: pt(50, 62, s))
        details.move(to: pt(26, 83, s)); details.addLine(to: pt(74, 83, s))
        ctx.stroke(details, with: .color(detail), style: strokeStyle(detailW))
        _ = rim
    }
}
