import SwiftUI
import BrillyDerCore

/// Crisp, zero-GPL, high-contrast chess piece renderer using filled Staunton silhouettes
/// with text presentation selector (`\u{FE0E}`) and custom rim contrast so White and Black
/// pieces pop cleanly on every board theme (Slate, Emerald, Walnut, Neon).
public struct ChessPieceView: View {
    let piece: Piece
    let squareSize: CGFloat

    public init(piece: Piece, squareSize: CGFloat) {
        self.piece = piece
        self.squareSize = squareSize
    }

    private var glyph: String {
        switch piece.type {
        case .king:   return "♚\u{FE0E}"
        case .queen:  return "♛\u{FE0E}"
        case .rook:   return "♜\u{FE0E}"
        case .bishop: return "♝\u{FE0E}"
        case .knight: return "♞\u{FE0E}"
        case .pawn:   return "♟\u{FE0E}"
        }
    }

    private var outlineGlyph: String {
        switch piece.type {
        case .king:   return "♔\u{FE0E}"
        case .queen:  return "♕\u{FE0E}"
        case .rook:   return "♖\u{FE0E}"
        case .bishop: return "♗\u{FE0E}"
        case .knight: return "♘\u{FE0E}"
        case .pawn:   return "♙\u{FE0E}"
        }
    }

    public var body: some View {
        let fontSize = max(14, squareSize * 0.78)
        ZStack {
            if piece.color == .white {
                // Dark crisp contour behind white piece
                Text(glyph)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.65))
                    .offset(y: 1.2)
                    .blur(radius: 0.6)

                Text(glyph)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color(hex: 0xE2E8F0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text(outlineGlyph)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundStyle(Color(hex: 0x0F172A).opacity(0.85))
            } else {
                // Subtle light rim behind black piece for dark-square visibility
                Text(glyph)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .offset(y: -0.6)

                Text(glyph)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: 0x1E293B), Color(hex: 0x020617)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text(outlineGlyph)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.22))
            }
        }
        .frame(width: squareSize, height: squareSize)
        .allowsHitTesting(false)
    }
}
