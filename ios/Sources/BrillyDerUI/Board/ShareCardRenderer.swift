import SwiftUI
import BrillyDerCore

/// Crisp social-ready share card view rendered via SwiftUI `ImageRenderer` into a shareable PNG image.
public struct BrillyShareCardView: View {
    let board: ChessBoard
    let orientation: PieceColor
    let theme: BoardThemeID
    let title: String
    let subtitle: String
    let evalDisplay: String
    let badgeText: String?
    let badgeColor: Color

    public init(
        board: ChessBoard,
        orientation: PieceColor,
        theme: BoardThemeID,
        title: String,
        subtitle: String,
        evalDisplay: String,
        badgeText: String? = nil,
        badgeColor: Color = BrillyPalette.brillyTeal
    ) {
        self.board = board
        self.orientation = orientation
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.evalDisplay = evalDisplay
        self.badgeText = badgeText
        self.badgeColor = badgeColor
    }

    public var body: some View {
        VStack(spacing: 14) {
            HStack {
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
                Spacer()
                if let badgeText {
                    Text(badgeText)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
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
                interactive: false
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
