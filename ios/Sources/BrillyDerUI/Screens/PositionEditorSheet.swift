import SwiftUI
import BrillyDerCore

public struct PositionEditorSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum ToolSelection: Equatable {
        case piece(Piece)
        case erase
    }

    @State private var squares: [Piece?] = ChessBoard().squares
    @State private var turn: PieceColor = .white
    @State private var castleWK = true
    @State private var castleWQ = true
    @State private var castleBK = true
    @State private var castleBQ = true
    @State private var activeTool: ToolSelection = .piece(Piece(color: .white, type: .queen))
    @State private var customFenInput: String = ""
    @State private var fenLoadError: String? = nil

    private var assembledFen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let p = squares[rank * 8 + file] {
                    if empty > 0 { row.append(String(empty)); empty = 0 }
                    row.append(p.fenChar)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row.append(String(empty)) }
            rows.append(row)
        }
        var c = ""
        if castleWK && squares[Square.e1.rawValue] == Piece(color: .white, type: .king) && squares[Square.h1.rawValue] == Piece(color: .white, type: .rook) { c.append("K") }
        if castleWQ && squares[Square.e1.rawValue] == Piece(color: .white, type: .king) && squares[Square.a1.rawValue] == Piece(color: .white, type: .rook) { c.append("Q") }
        if castleBK && squares[Square.e8.rawValue] == Piece(color: .black, type: .king) && squares[Square.h8.rawValue] == Piece(color: .black, type: .rook) { c.append("k") }
        if castleBQ && squares[Square.e8.rawValue] == Piece(color: .black, type: .king) && squares[Square.a8.rawValue] == Piece(color: .black, type: .rook) { c.append("q") }
        let castlingStr = c.isEmpty ? "-" : c
        return "\(rows.joined(separator: "/")) \(turn.rawValue) \(castlingStr) - 0 1"
    }

    private var validationError: String? {
        var wKing: Square?
        var bKing: Square?
        var wCount = 0
        var bCount = 0
        for idx in 0..<64 {
            guard let p = squares[idx] else { continue }
            let sq = Square(unchecked: idx)
            if p.type == .pawn && (sq.rank == 0 || sq.rank == 7) {
                return "Pawns cannot sit on rank 1 or rank 8."
            }
            if p.type == .king {
                if p.color == .white { wKing = sq; wCount += 1 }
                else { bKing = sq; bCount += 1 }
            }
        }
        if wCount != 1 || bCount != 1 { return "Place exactly 1 White king and 1 Black king." }
        if let wk = wKing, let bk = bKing, abs(wk.file - bk.file) <= 1 && abs(wk.rank - bk.rank) <= 1 {
            return "Kings cannot stand on adjacent squares."
        }
        guard let board = try? ChessBoard(fen: assembledFen) else { return "Invalid board position." }
        if board.isInCheck(turn.opposite) {
            return "Side not to move cannot already be in check."
        }
        return nil
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(spacing: 14) {
                        // Quick Presets
                        HStack(spacing: 8) {
                            presetButton("Start") { loadFen(ChessBoard.initialFEN) }
                            presetButton("Kings Only") { loadFen("4k3/8/8/8/8/8/8/4K3 w - - 0 1") }
                            presetButton("Lucena") { loadFen("1K1k4/1P6/8/8/8/8/r7/2R5 w - - 0 1") }
                            presetButton("Clear") {
                                squares = Array(repeating: nil, count: 64)
                                fenLoadError = nil
                            }
                        }

                        // Editable 8x8 Grid
                        GeometryReader { geo in
                            let side = min(geo.size.width, geo.size.height)
                            let sqSize = side / 8.0
                            VStack(spacing: 0) {
                                ForEach(0..<8, id: \.self) { row in
                                    HStack(spacing: 0) {
                                        ForEach(0..<8, id: \.self) { col in
                                            let sq = Square(unchecked: (7 - row) * 8 + col)
                                            ZStack {
                                                sq.isLightSquare ? store.boardTheme.lightSquare : store.boardTheme.darkSquare
                                                if let piece = squares[sq.rawValue] {
                                                    ChessPieceView(piece: piece, squareSize: sqSize)
                                                }
                                            }
                                            .frame(width: sqSize, height: sqSize)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                applyTool(to: sq)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(width: side, height: side)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .frame(maxWidth: .infinity)
                        }
                        .aspectRatio(1, contentMode: .fit)

                        // Compact 6-wide Piece Palette + Dedicated Eraser Toggle (fits 375pt iPhone SE cleanly)
                        VStack(spacing: 8) {
                            paletteRow(color: .white)
                            paletteRow(color: .black)

                            let erasing = activeTool == .erase
                            Button {
                                activeTool = .erase
                                store.triggerHaptic(.move)
                            } label: {
                                Label(erasing ? "Eraser Active (Tap Squares to Remove)" : "Eraser Tool", systemImage: "eraser.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(erasing ? BrillyPalette.blunderRose : BrillyPalette.inkSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(erasing ? BrillyPalette.blunderRose.opacity(0.22) : Color.white.opacity(0.06))
                                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(erasing ? BrillyPalette.blunderRose : .clear, lineWidth: 1.2))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .brillySurface(store.surfaceStyle, cornerRadius: 16)

                        // Side to Move + Castling Rights + FEN Paste
                        VStack(spacing: 10) {
                            HStack {
                                Text("Side to Move")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Spacer()
                                Picker("Turn", selection: $turn) {
                                    Text("White").tag(PieceColor.white)
                                    Text("Black").tag(PieceColor.black)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 160)
                            }

                            HStack(spacing: 6) {
                                Text("Castling")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                Spacer()
                                castlePill("W O-O", isOn: $castleWK)
                                castlePill("W O-O-O", isOn: $castleWQ)
                                castlePill("B O-O", isOn: $castleBK)
                                castlePill("B O-O-O", isOn: $castleBQ)
                            }

                            HStack(spacing: 8) {
                                TextField("Paste FEN…", text: $customFenInput)
                                    .textFieldStyle(.plain)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    #endif
                                    .onSubmit { loadFen(customFenInput) }
                                    .font(.caption.monospaced())
                                    .padding(9)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Button("Load") {
                                    loadFen(customFenInput)
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.voidBg)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BrillyPalette.brillyTeal))
                                .buttonStyle(.plain)
                            }

                            if let fenLoadError {
                                Label(fenLoadError, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(BrillyPalette.blunderRose)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                        .brillySurface(store.surfaceStyle, cornerRadius: 16)

                        if let err = validationError {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BrillyPalette.blunderRose)
                        }

                        Button {
                            guard validationError == nil else { return }
                            let fen = assembledFen
                            dismiss()
                            store.openCustomFEN(fen)
                        } label: {
                            Label("Analyze Position", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(BrillyPalette.voidBg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(validationError == nil ? BrillyPalette.brillyTeal : Color.gray.opacity(0.4))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(validationError != nil)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Board / FEN Editor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func paletteRow(color: PieceColor) -> some View {
        HStack(spacing: 6) {
            ForEach([PieceType.king, .queen, .rook, .bishop, .knight, .pawn], id: \.self) { t in
                let piece = Piece(color: color, type: t)
                let sel = activeTool == .piece(piece)
                Button {
                    activeTool = .piece(piece)
                    store.triggerHaptic(.move)
                } label: {
                    ChessPieceView(piece: piece, squareSize: 32)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(sel ? BrillyPalette.brillyTeal.opacity(0.30) : Color.white.opacity(color == .black ? 0.14 : 0.06))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(sel ? BrillyPalette.brillyTeal : .clear, lineWidth: 1.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func castlePill(_ label: String, isOn: Binding<Bool>) -> some View {
        Button(label) {
            isOn.wrappedValue.toggle()
            store.triggerHaptic(.move)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(isOn.wrappedValue ? BrillyPalette.voidBg : BrillyPalette.inkSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Capsule().fill(isOn.wrappedValue ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
        .buttonStyle(.plain)
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            store.triggerHaptic(.move)
            action()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(BrillyPalette.inkPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
        .buttonStyle(.plain)
    }

    private func applyTool(to sq: Square) {
        switch activeTool {
        case .erase:
            squares[sq.rawValue] = nil
        case .piece(let piece):
            if squares[sq.rawValue] == piece {
                squares[sq.rawValue] = nil
            } else {
                squares[sq.rawValue] = piece
            }
        }
        fenLoadError = nil
        store.triggerHaptic(.move)
    }

    private func loadFen(_ fen: String) {
        let trimmed = fen.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fenLoadError = "Paste a FEN string first."
            return
        }
        do {
            let b = try ChessBoard(fen: trimmed)
            squares = b.squares
            turn = b.turn
            castleWK = b.castling.contains(.whiteKingside)
            castleWQ = b.castling.contains(.whiteQueenside)
            castleBK = b.castling.contains(.blackKingside)
            castleBQ = b.castling.contains(.blackQueenside)
            fenLoadError = nil
            store.triggerHaptic(.success)
        } catch {
            fenLoadError = "Invalid FEN: \(error.localizedDescription)"
            store.triggerHaptic(.error)
        }
    }
}
