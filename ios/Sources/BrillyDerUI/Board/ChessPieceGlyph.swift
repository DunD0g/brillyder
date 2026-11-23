import SwiftUI
import BrillyDerCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Thread-safe, in-memory Retina sprite cache for all bundled pro chess piece sets
/// (`cburnett` BSD-3-Clause, `chessnut` Apache-2.0, `spatial` MIT, `kiwen` CC-BY-4.0).
@MainActor
public enum PieceSpriteCache {
    #if canImport(UIKit)
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 64
        return c
    }()

    public static func uiImage(set: PieceSetID, piece: Piece) -> UIImage? {
        let name = resourceName(set: set, piece: piece)
        if let hit = cache.object(forKey: name as NSString) {
            return hit
        }
        guard let url = resourceURL(named: name),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data, scale: 3.0) else {
            return nil
        }
        cache.setObject(img, forKey: name as NSString)
        return img
    }
    #elseif canImport(AppKit)
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    public static func nsImage(set: PieceSetID, piece: Piece) -> NSImage? {
        let name = resourceName(set: set, piece: piece)
        if let hit = cache.object(forKey: name as NSString) {
            return hit
        }
        guard let url = resourceURL(named: name),
              let img = NSImage(contentsOf: url) else {
            return nil
        }
        cache.setObject(img, forKey: name as NSString)
        return img
    }
    #endif

    public static func resourceName(set: PieceSetID, piece: Piece) -> String {
        let colorPrefix = piece.color == .white ? "w" : "b"
        let typeChar: String
        switch piece.type {
        case .king:   typeChar = "K"
        case .queen:  typeChar = "Q"
        case .rook:   typeChar = "R"
        case .bishop: typeChar = "B"
        case .knight: typeChar = "N"
        case .pawn:   typeChar = "P"
        }
        return "\(set.rawValue)_\(colorPrefix)\(typeChar)"
    }

    public static func resourceURL(named name: String) -> URL? {
        if let direct = Bundle.module.url(forResource: name, withExtension: "png") {
            return direct
        }
        return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Pieces")
    }
}

/// Tournament-grade Retina chess piece renderer supporting live piece set switching
/// via `@Environment(\.brillyPieceSet)` or explicit `pieceSet:` override.
public struct ChessPieceView: View {
    @Environment(\.brillyPieceSet) private var envPieceSet

    let piece: Piece
    let squareSize: CGFloat
    let explicitPieceSet: PieceSetID?

    public init(piece: Piece, squareSize: CGFloat, pieceSet: PieceSetID? = nil) {
        self.piece = piece
        self.squareSize = squareSize
        self.explicitPieceSet = pieceSet
    }

    private var activeSet: PieceSetID {
        explicitPieceSet ?? envPieceSet
    }

    public var body: some View {
        let spriteSize = squareSize * 0.92
        Group {
            #if canImport(UIKit)
            if let uiImg = PieceSpriteCache.uiImage(set: activeSet, piece: piece) {
                Image(uiImage: uiImg)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: spriteSize, height: spriteSize)
                    .shadow(
                        color: Color.black.opacity(piece.color == .white ? 0.24 : 0.34),
                        radius: max(0.8, squareSize * 0.03),
                        y: max(0.4, squareSize * 0.02)
                    )
            } else {
                fallbackGlyph
            }
            #elseif canImport(AppKit)
            if let nsImg = PieceSpriteCache.nsImage(set: activeSet, piece: piece) {
                Image(nsImage: nsImg)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: spriteSize, height: spriteSize)
                    .shadow(
                        color: Color.black.opacity(piece.color == .white ? 0.24 : 0.34),
                        radius: max(0.8, squareSize * 0.03),
                        y: max(0.4, squareSize * 0.02)
                    )
            } else {
                fallbackGlyph
            }
            #else
            fallbackGlyph
            #endif
        }
        .frame(width: squareSize, height: squareSize)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var fallbackGlyph: some View {
        Text(String(piece.fenChar))
            .font(.system(size: squareSize * 0.55, weight: .bold, design: .rounded))
            .foregroundStyle(piece.color == .white ? Color.white : Color.black)
    }
}
