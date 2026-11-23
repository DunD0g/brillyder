import SwiftUI
import UniformTypeIdentifiers
import BrillyDerCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Lazy `Transferable` wrapper for BrillyDer position share cards:
/// Defers `ImageRenderer` rasterization until the user actually invokes the Share Sheet, keeping 120Hz scrolling smooth.
public struct BrillyShareCardItem: Transferable, Sendable {
    public let fen: String
    public let orientation: PieceColor
    public let theme: BoardThemeID
    public let title: String
    public let subtitle: String
    public let evalDisplay: String
    public let badgeText: String?
    public let classification: MoveClassification?
    public let lastMoveFrom: Square?
    public let lastMoveTo: Square?

    public init(
        fen: String,
        orientation: PieceColor,
        theme: BoardThemeID,
        title: String,
        subtitle: String,
        evalDisplay: String,
        badgeText: String? = nil,
        classification: MoveClassification? = nil,
        lastMove: (from: Square, to: Square)? = nil
    ) {
        self.fen = fen
        self.orientation = orientation
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.evalDisplay = evalDisplay
        self.badgeText = badgeText
        self.classification = classification
        self.lastMoveFrom = lastMove?.from
        self.lastMoveTo = lastMove?.to
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            await MainActor.run {
                item.renderPNGData()
            }
        }
    }

    @MainActor
    public func renderPNGData() -> Data {
        let board = (try? ChessBoard(fen: fen)) ?? ChessBoard()
        let lastMoveTuple: (from: Square, to: Square)? = {
            if let f = lastMoveFrom, let t = lastMoveTo { return (f, t) }
            return nil
        }()
        let badgeOverlay: MoveBadgeOverlay? = {
            if let cls = classification, let to = lastMoveTo {
                return MoveBadgeOverlay(square: to, classification: cls)
            }
            return nil
        }()
        let card = BrillyShareCardView(
            board: board,
            orientation: orientation,
            theme: theme,
            title: title,
            subtitle: subtitle,
            evalDisplay: evalDisplay,
            badgeText: badgeText,
            classification: classification,
            lastMove: lastMoveTuple,
            moveBadge: badgeOverlay
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0
        #if canImport(UIKit)
        return renderer.uiImage?.pngData() ?? Data()
        #elseif canImport(AppKit)
        if let nsImg = renderer.nsImage,
           let tiff = nsImg.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return Data()
        #else
        return Data()
        #endif
    }
}

/// Crisp social-ready share card view rendered via SwiftUI `ImageRenderer` into a shareable PNG image.
public struct BrillyShareCardView: View {
    let board: ChessBoard
    let orientation: PieceColor
    let theme: BoardThemeID
    let title: String
    let subtitle: String
    let evalDisplay: String
    let badgeText: String?
    let classification: MoveClassification?
    let badgeColor: Color
    let lastMove: (from: Square, to: Square)?
    let moveBadge: MoveBadgeOverlay?

    public init(
        board: ChessBoard,
        orientation: PieceColor,
        theme: BoardThemeID,
        title: String,
        subtitle: String,
        evalDisplay: String,
        badgeText: String? = nil,
        classification: MoveClassification? = nil,
        badgeColor: Color? = nil,
        lastMove: (from: Square, to: Square)? = nil,
        moveBadge: MoveBadgeOverlay? = nil
    ) {
        self.board = board
        self.orientation = orientation
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.evalDisplay = evalDisplay
        self.badgeText = badgeText
        self.classification = classification
        self.badgeColor = badgeColor ?? classification.map(BrillyPalette.color(for:)) ?? BrillyPalette.brillyTeal
        self.lastMove = lastMove
        self.moveBadge = moveBadge
    }

    public var body: some View {
        let badgeInk: Color = classification.map(BrillyPalette.badgeForeground(for:)) ?? Color(hex: 0x070B14)
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    BrillyGemIcon(size: 20, color: BrillyPalette.brillyTeal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BRILLYDER")
                            .font(.caption.weight(.black))
                            .tracking(1.6)
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Text(title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let badgeText {
                    HStack(spacing: 4) {
                        if classification == .book {
                            Image(systemName: "book.fill")
                                .font(.caption2.weight(.bold))
                        } else if classification == .best {
                            Image(systemName: "star.fill")
                                .font(.caption2.weight(.bold))
                        }
                        Text(badgeText)
                            .font(.caption.weight(.black))
                    }
                    .foregroundStyle(badgeInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(badgeColor))
                }
            }

            InteractiveChessBoardView(
                board: board,
                orientation: orientation,
                theme: theme,
                surfaceStyle: .cosmic,
                interactive: false,
                lastMove: lastMove,
                moveBadge: moveBadge
            )
            .frame(width: 320, height: 320)

            HStack {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .lineLimit(1)
                Spacer()
                Text("Eval \(evalDisplay)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(BrillyPalette.brillyTeal)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x0F172A), Color(hex: 0x070B14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(BrillyPalette.brillyTeal.opacity(0.35), lineWidth: 1.5)
        )
    }

    @MainActor
    public func renderImage() -> Image? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2.0
        #if canImport(UIKit)
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        #elseif canImport(AppKit)
        if let nsImage = renderer.nsImage {
            return Image(nsImage: nsImage)
        }
        #endif
        return nil
    }
}
