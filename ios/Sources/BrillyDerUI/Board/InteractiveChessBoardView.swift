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

/// 120Hz native SwiftUI interactive chessboard (tap-to-move + drag-to-move, legal & en-passant hints,
/// single-layer vector coaching arrows, rank-8 safe classification badge, dismissible promotion overlay).
public struct InteractiveChessBoardView: View {
    private struct BoardDragState: Equatable {
        var fromSquare: Square? = nil
        var location: CGPoint? = nil
    }

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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.brillyShowCoordinates) private var showBoardCoordinates
    @State private var selectedSquare: Square? = nil
    @GestureState private var dragState = BoardDragState()
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

    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let sqSize = side / 8.0
            let checkedKingSq: Square? = board.isInCheck() ? board.kingSquare(for: board.turn) : nil

            // Compute once per frame before the 8x8 grid (eliminates 64x redundant legalMoves() calls)
            let activeSource = dragState.fromSquare ?? selectedSquare
            let activeLegalMoves: [ChessMove] = activeSource.map { board.legalMoves(from: $0) } ?? []
            let legalTargets = Set(activeLegalMoves.map(\.to))
            let epCaptureSq: Square? = {
                guard let src = activeSource,
                      board[src]?.type == .pawn,
                      let ep = board.enPassantSquare,
                      legalTargets.contains(ep) else { return nil }
                return ep
            }()
            let highlightMap: [String: ArrowKind] = Dictionary(
                highlights.map { ($0.square.lowercased(), $0.color) },
                uniquingKeysWith: { _, latest in latest }
            )

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
                                    activeSource: activeSource,
                                    legalTargets: legalTargets,
                                    epCaptureSq: epCaptureSq,
                                    highlightColor: highlightMap[sq.algebraic],
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

                // 2. Single-layer Vector Coaching Arrows (no alpha overlap seam between shaft & head)
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

                // 3. Move Classification Badge (safely inside upper-right corner — never clipped on rank 8)
                if let badge = moveBadge, sqSize >= 20 {
                    let pt = topRightCorner(for: badge.square, sqSize: sqSize)
                    let badgeSize = max(18, sqSize * 0.36)
                    let fg = BrillyPalette.badgeForeground(for: badge.classification)
                    ZStack {
                        Circle()
                            .fill(BrillyPalette.color(for: badge.classification))
                        if badge.classification == .book {
                            Image(systemName: "book.fill")
                                .font(.system(size: badgeSize * 0.48, weight: .bold))
                                .foregroundStyle(fg)
                        } else if badge.classification == .best {
                            Image(systemName: "star.fill")
                                .font(.system(size: badgeSize * 0.48, weight: .bold))
                                .foregroundStyle(fg)
                        } else {
                            Text(badge.classification.symbol)
                                .font(.system(size: badgeSize * 0.54, weight: .black, design: .rounded))
                                .foregroundStyle(fg)
                        }
                    }
                    .frame(width: badgeSize, height: badgeSize)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 2.5, y: 1)
                    .position(x: pt.x - badgeSize * 0.52, y: pt.y + badgeSize * 0.52)
                    .allowsHitTesting(false)
                }

                // 4. Lifted Dragged Piece (auto-resets on system cancellation via @GestureState)
                if let fromSq = dragState.fromSquare,
                   let loc = dragState.location,
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
                    .updating($dragState) { value, state, _ in
                        guard interactive, pendingPromotion == nil else { return }
                        if state.fromSquare == nil {
                            if hypot(value.translation.width, value.translation.height) > 8,
                               let sq = squareAt(point: value.startLocation, sqSize: sqSize),
                               let piece = board[sq],
                               piece.color == board.turn {
                                state.fromSquare = sq
                                state.location = value.location
                            }
                        } else {
                            state.location = value.location
                        }
                    }
                    .onEnded { value in
                        guard interactive, pendingPromotion == nil else { return }
                        let distance = hypot(value.translation.width, value.translation.height)
                        if distance > 10 {
                            guard let fromSq = squareAt(point: value.startLocation, sqSize: sqSize),
                                  let piece = board[fromSq],
                                  piece.color == board.turn else { return }
                            // Hit-test at the lifted piece's visual center so drops feel spot-on under thumbs
                            let dropPoint = CGPoint(x: value.location.x, y: value.location.y - sqSize * 0.25)
                            if let toSq = squareAt(point: dropPoint, sqSize: sqSize), toSq != fromSq {
                                attemptMove(from: fromSq, to: toSq)
                            } else {
                                selectedSquare = fromSq
                            }
                        } else if let tappedSq = squareAt(point: value.location, sqSize: sqSize) {
                            handleSquareTap(tappedSq, legalTargets: legalTargets)
                        }
                    },
                including: (interactive && pendingPromotion == nil) ? .all : .none
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        #if os(iOS)
        .frame(maxWidth: horizontalSizeClass == .regular ? 520 : .infinity)
        .frame(maxWidth: .infinity)
        #endif
        .onChange(of: board.fen) { _, _ in
            selectedSquare = nil
            pendingPromotion = nil
        }
        .onChange(of: interactive) { _, isNowInteractive in
            if !isNowInteractive {
                selectedSquare = nil
                pendingPromotion = nil
            }
        }
        .onChange(of: orientation) { _, _ in
            selectedSquare = nil
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
        activeSource: Square?,
        legalTargets: Set<Square>,
        epCaptureSq: Square?,
        highlightColor: ArrowKind?,
        checkedKingSq: Square?
    ) -> some View {
        let isLight = sq.isLightSquare
        let isSelected = activeSource == sq
        let isLast = lastMove?.from == sq || lastMove?.to == sq
        let isLegalDest = legalTargets.contains(sq)
        let piece = board[sq]
        let isHiddenByDrag = dragState.fromSquare == sq
        let showCoords = showBoardCoordinates && sqSize >= 22
        let plySeed = max(0, (board.fullmoveNumber - 1) * 2 + (board.turn == .black ? 1 : 0))
        let colors = theme.squareColors(plySeed: plySeed)

        ZStack {
            (isLight ? colors.light : colors.dark)

            if isLast {
                theme.lastMove
            }
            if let hlColor = highlightColor {
                BrillyPalette.color(for: hlColor).opacity(0.32)
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

            if showCoords && col == 0 {
                Text(String(sq.rankChar))
                    .font(.system(size: max(8, sqSize * 0.19), weight: .bold, design: .rounded))
                    .foregroundStyle(theme.coordColor(isLightSquare: isLight))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(2)
                    .accessibilityHidden(true)
            }
            if showCoords && row == 7 {
                Text(String(sq.fileChar))
                    .font(.system(size: max(8, sqSize * 0.19), weight: .bold, design: .rounded))
                    .foregroundStyle(theme.coordColor(isLightSquare: isLight))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(2)
                    .accessibilityHidden(true)
            }

            if isLegalDest {
                if piece != nil || epCaptureSq == sq {
                    Circle()
                        .strokeBorder(theme.accent.opacity(0.84), lineWidth: max(3, sqSize * 0.09))
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

    // MARK: - Promotion Picker (Dismissible & High-Contrast!)

    @ViewBuilder
    private func promotionOverlay(
        promo: (from: Square, to: Square, color: PieceColor),
        boardSide: CGFloat,
        sqSize: CGFloat
    ) -> some View {
        ZStack {
            Color.black.opacity(0.58)
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
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(promo.color == .black ? Color(hex: 0xCBD5E1).opacity(0.28) : Color.white.opacity(0.08))
                                )
                                .brillySurface(surfaceStyle, cornerRadius: 14, tint: BrillyPalette.brillyTeal, interactive: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Promote to \(promotionTitle(for: choice))")
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

    private func promotionTitle(for type: PieceType) -> String {
        switch type {
        case .queen: return "Queen"
        case .rook: return "Rook"
        case .bishop: return "Bishop"
        case .knight: return "Knight"
        default: return "Piece"
        }
    }

    // MARK: - Interaction Helpers

    private func handleSquareTap(_ sq: Square, legalTargets: Set<Square>) {
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

    /// Unified single-polygon arrow drawn cleanly with zero alpha double-blending at the head-shaft junction.
    private func drawArrow(in ctx: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color, cellSize: CGFloat) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len > 1 else { return }
        let ux = dx / len
        let uy = dy / len
        let perpX = -uy
        let perpY = ux

        let halfShaft = cellSize * 0.072
        let headLen = min(len * 0.55, cellSize * 0.34)
        let headHalfWidth = cellSize * 0.22
        let neck = CGPoint(x: to.x - ux * headLen, y: to.y - uy * headLen)
        let tailStart = CGPoint(x: from.x + ux * (cellSize * 0.08), y: from.y + uy * (cellSize * 0.08))

        var arrow = Path()
        arrow.move(to: CGPoint(x: tailStart.x + perpX * halfShaft, y: tailStart.y + perpY * halfShaft))
        arrow.addLine(to: CGPoint(x: neck.x + perpX * halfShaft, y: neck.y + perpY * halfShaft))
        arrow.addLine(to: CGPoint(x: neck.x + perpX * headHalfWidth, y: neck.y + perpY * headHalfWidth))
        arrow.addLine(to: to)
        arrow.addLine(to: CGPoint(x: neck.x - perpX * headHalfWidth, y: neck.y - perpY * headHalfWidth))
        arrow.addLine(to: CGPoint(x: neck.x - perpX * halfShaft, y: neck.y - perpY * halfShaft))
        arrow.addLine(to: CGPoint(x: tailStart.x - perpX * halfShaft, y: tailStart.y - perpY * halfShaft))
        arrow.closeSubpath()

        ctx.fill(arrow, with: .color(color))
    }
}
