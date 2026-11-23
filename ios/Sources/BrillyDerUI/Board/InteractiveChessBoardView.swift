import SwiftUI
import BrillyDerCore

public struct MoveBadgeOverlay: Equatable, Sendable {
    public let square: Square
    public let classification: MoveClassification

    public init(square: Square, classification: MoveClassification) {
        self.square = square
        self.classification = classification
    }
}

/// 120Hz native SwiftUI interactive chessboard (tap-to-move + drag-to-move, legal hints,
/// coaching arrows, rank-8 safe classification badge, dismissible promotion overlay).
public struct InteractiveChessBoardView: View {
    let board: ChessBoard
    let orientation: PieceColor
    let theme: BoardThemeID
    let surfaceStyle: SurfaceStyle
    let interactive: Bool
    let lastMove: (from: Square, to: Square)?
    let arrows: [BoardArrow]
    let highlights: [SquareHighlight]
    let moveBadge: MoveBadgeOverlay?
    let onMove: ((ChessMove) -> Void)?

    @State private var selectedSquare: Square? = nil
    @State private var draggedFrom: Square? = nil
    @State private var dragLocation: CGPoint? = nil
    @State private var pendingPromotion: (from: Square, to: Square, color: PieceColor)? = nil

    public init(
        board: ChessBoard,
        orientation: PieceColor = .white,
        theme: BoardThemeID = .slate,
        surfaceStyle: SurfaceStyle = .liquidGlass,
        interactive: Bool = true,
        lastMove: (from: Square, to: Square)? = nil,
        arrows: [BoardArrow] = [],
        highlights: [SquareHighlight] = [],
        moveBadge: MoveBadgeOverlay? = nil,
        onMove: ((ChessMove) -> Void)? = nil
    ) {
        self.board = board
        self.orientation = orientation
        self.theme = theme
        self.surfaceStyle = surfaceStyle
        self.interactive = interactive
        self.lastMove = lastMove
        self.arrows = arrows
        self.highlights = highlights
        self.moveBadge = moveBadge
        self.onMove = onMove
    }

    private var legalFromSelected: [ChessMove] {
        guard let sq = selectedSquare ?? draggedFrom else { return [] }
        return board.legalMoves(from: sq)
    }

    private var legalTargets: Set<Square> {
        Set(legalFromSelected.map(\.to))
    }

    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let sqSize = side / 8.0
            let checkedKingSq: Square? = board.isInCheck() ? board.kingSquare(for: board.turn) : nil

            ZStack(alignment: .topLeading) {
                // 1. 64 Squares Grid
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { col in
                                let sq = squareFor(row: row, col: col)
                                squareCell(
                                    sq: sq,
                                    row: row,
                                    col: col,
                                    sqSize: sqSize,
                                    checkedKingSq: checkedKingSq
                                )
                            }
                        }
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(surfaceStyle == .liquidGlass ? 0.22 : 0.12), lineWidth: 1)
                )

                // 2. Vector Coaching Arrows
                if !arrows.isEmpty {
                    Canvas { ctx, size in
                        let cell = size.width / 8.0
                        for arrow in arrows {
                            guard let fromSq = Square(algebraic: arrow.from),
                                  let toSq = Square(algebraic: arrow.to) else { continue }
                            let p1 = centerPoint(for: fromSq, sqSize: cell)
                            let p2 = centerPoint(for: toSq, sqSize: cell)
                            drawArrow(in: &ctx, from: p1, to: p2, color: BrillyPalette.color(for: arrow.color), cellSize: cell)
                        }
                    }
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
                }

                // 3. Move Classification Badge (safely inside upper-right corner — never clipped on rank 8!)
                if let badge = moveBadge {
                    let pt = topRightCorner(for: badge.square, sqSize: sqSize)
                    let badgeSize = max(16, sqSize * 0.34)
                    Text(badge.classification.symbol)
                        .font(.system(size: badgeSize * 0.56, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: badgeSize, height: badgeSize)
                        .background(Circle().fill(BrillyPalette.color(for: badge.classification)))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1))
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .position(x: pt.x - badgeSize * 0.52, y: pt.y + badgeSize * 0.52)
                        .allowsHitTesting(false)
                }

                // 4. Lifted Dragged Piece
                if let fromSq = draggedFrom,
                   let loc = dragLocation,
                   let piece = board[fromSq] {
                    ChessPieceView(piece: piece, squareSize: sqSize * 1.18)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                        .position(x: loc.x, y: loc.y - sqSize * 0.25)
                        .allowsHitTesting(false)
                }

                // 5. Dismissible Promotion Picker Overlay
                if let promo = pendingPromotion {
                    promotionOverlay(promo: promo, boardSide: side, sqSize: sqSize)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard interactive, pendingPromotion == nil else { return }
                        if draggedFrom == nil {
                            if let sq = squareAt(point: value.startLocation, sqSize: sqSize),
                               let piece = board[sq],
                               piece.color == board.turn {
                                // Only start visual lift once finger actually moves
                                if hypot(value.translation.width, value.translation.height) > 6 {
                                    draggedFrom = sq
                                    selectedSquare = sq
                                    dragLocation = value.location
                                }
                            }
                        } else {
                            dragLocation = value.location
                        }
                    }
                    .onEnded { value in
                        guard interactive, pendingPromotion == nil else {
                            draggedFrom = nil
                            dragLocation = nil
                            return
                        }
                        if let fromSq = draggedFrom {
                            draggedFrom = nil
                            dragLocation = nil
                            if let toSq = squareAt(point: value.location, sqSize: sqSize), toSq != fromSq {
                                attemptMove(from: fromSq, to: toSq)
                            }
                        } else if let tappedSq = squareAt(point: value.location, sqSize: sqSize) {
                            handleSquareTap(tappedSq)
                        }
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: board.fen) { _, _ in
            selectedSquare = nil
            draggedFrom = nil
            dragLocation = nil
            pendingPromotion = nil
        }
    }

    // MARK: - Square Rendering

    @ViewBuilder
    private func squareCell(
        sq: Square,
        row: Int,
        col: Int,
        sqSize: CGFloat,
        checkedKingSq: Square?
    ) -> some View {
        let isLight = sq.isLightSquare
        let isSelected = selectedSquare == sq
        let isLast = lastMove?.from == sq || lastMove?.to == sq
        let isLegalDest = legalTargets.contains(sq)
        let highlight = highlights.first { $0.square.lowercased() == sq.algebraic }
        let piece = board[sq]
        let isHiddenByDrag = draggedFrom == sq

        ZStack {
            (isLight ? theme.lightSquare : theme.darkSquare)

            if isLast {
                theme.lastMove
            }
            if let hl = highlight {
                BrillyPalette.color(for: hl.color).opacity(0.32)
            }
            if isSelected {
                theme.selected
            }
            if checkedKingSq == sq {
                RadialGradient(
                    colors: [Color.red.opacity(0.92), Color.red.opacity(0.0)],
                    center: .center,
                    startRadius: sqSize * 0.08,
                    endRadius: sqSize * 0.56
                )
            }

            // Rank & file coordinates along bottom-right / top-left edges
            if col == 0 {
                Text(String(sq.rankChar))
                    .font(.system(size: max(8, sqSize * 0.19), weight: .bold, design: .rounded))
                    .foregroundStyle((isLight ? theme.darkSquare : theme.lightSquare).opacity(0.88))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(2)
            }
            if row == 7 {
                Text(String(sq.fileChar))
                    .font(.system(size: max(8, sqSize * 0.19), weight: .bold, design: .rounded))
                    .foregroundStyle((isLight ? theme.darkSquare : theme.lightSquare).opacity(0.88))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(2)
            }

            // Legal move target indicators
            if isLegalDest {
                if piece != nil {
                    Circle()
                        .strokeBorder(theme.accent.opacity(0.82), lineWidth: max(3, sqSize * 0.09))
                        .padding(sqSize * 0.06)
                } else {
                    Circle()
                        .fill(theme.accent.opacity(0.62))
                        .frame(width: sqSize * 0.30, height: sqSize * 0.30)
                }
            }

            if let piece, !isHiddenByDrag {
                ChessPieceView(piece: piece, squareSize: sqSize)
            }
        }
        .frame(width: sqSize, height: sqSize)
    }

    // MARK: - Promotion Picker (Dismissible!)

    @ViewBuilder
    private func promotionOverlay(
        promo: (from: Square, to: Square, color: PieceColor),
        boardSide: CGFloat,
        sqSize: CGFloat
    ) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    pendingPromotion = nil
                }

            VStack(spacing: 12) {
                Text("Promote Pawn")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkPrimary)

                HStack(spacing: 10) {
                    ForEach(PieceType.promotionChoices, id: \.self) { choice in
                        Button {
                            let move = ChessMove(from: promo.from, to: promo.to, promotion: choice)
                            pendingPromotion = nil
                            selectedSquare = nil
                            onMove?(move)
                        } label: {
                            ChessPieceView(piece: Piece(color: promo.color, type: choice), squareSize: max(46, sqSize * 0.95))
                                .padding(6)
                                .brillySurface(surfaceStyle, cornerRadius: 14, tint: BrillyPalette.brillyTeal, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Cancel") {
                    pendingPromotion = nil
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BrillyPalette.inkSecondary)
                .padding(.top, 2)
            }
            .padding(18)
            .brillySurface(surfaceStyle, cornerRadius: 22)
        }
        .frame(width: boardSide, height: boardSide)
    }

    // MARK: - Interaction Helpers

    private func handleSquareTap(_ sq: Square) {
        if let selected = selectedSquare {
            if selected == sq {
                selectedSquare = nil
                return
            }
            if legalTargets.contains(sq) {
                attemptMove(from: selected, to: sq)
                return
            }
        }
        if let piece = board[sq], piece.color == board.turn {
            selectedSquare = sq
        } else {
            selectedSquare = nil
        }
    }

    private func attemptMove(from: Square, to: Square) {
        let matching = board.legalMoves(from: from).filter { $0.to == to }
        guard !matching.isEmpty else {
            selectedSquare = nil
            return
        }
        if matching.count > 1, matching.allSatisfy({ $0.promotion != nil }) {
            pendingPromotion = (from: from, to: to, color: board.turn)
            return
        }
        selectedSquare = nil
        onMove?(matching[0])
    }

    // MARK: - Coordinate Mapping

    private func squareFor(row: Int, col: Int) -> Square {
        let rank = orientation == .white ? (7 - row) : row
        let file = orientation == .white ? col : (7 - col)
        return Square(unchecked: rank * 8 + file)
    }

    private func squareAt(point: CGPoint, sqSize: CGFloat) -> Square? {
        guard sqSize > 0 else { return nil }
        let col = Int(floor(point.x / sqSize))
        let row = Int(floor(point.y / sqSize))
        guard (0..<8).contains(col), (0..<8).contains(row) else { return nil }
        return squareFor(row: row, col: col)
    }

    private func centerPoint(for sq: Square, sqSize: CGFloat) -> CGPoint {
        let col = orientation == .white ? sq.file : (7 - sq.file)
        let row = orientation == .white ? (7 - sq.rank) : sq.rank
        return CGPoint(x: (CGFloat(col) + 0.5) * sqSize, y: (CGFloat(row) + 0.5) * sqSize)
    }

    private func topRightCorner(for sq: Square, sqSize: CGFloat) -> CGPoint {
        let col = orientation == .white ? sq.file : (7 - sq.file)
        let row = orientation == .white ? (7 - sq.rank) : sq.rank
        return CGPoint(x: CGFloat(col + 1) * sqSize, y: CGFloat(row) * sqSize)
    }

    private func drawArrow(in ctx: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color, cellSize: CGFloat) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len > 1 else { return }
        let ux = dx / len
        let uy = dy / len

        let headLen = cellSize * 0.34
        let headHalfWidth = cellSize * 0.22
        let shaftEnd = CGPoint(x: to.x - ux * headLen * 0.85, y: to.y - uy * headLen * 0.85)

        var shaft = Path()
        shaft.move(to: from)
        shaft.addLine(to: shaftEnd)
        ctx.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: cellSize * 0.14, lineCap: .round))

        let perpX = -uy
        let perpY = ux
        var head = Path()
        head.move(to: to)
        head.addLine(to: CGPoint(x: to.x - ux * headLen + perpX * headHalfWidth, y: to.y - uy * headLen + perpY * headHalfWidth))
        head.addLine(to: CGPoint(x: to.x - ux * headLen - perpX * headHalfWidth, y: to.y - uy * headLen - perpY * headHalfWidth))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))
    }
}
