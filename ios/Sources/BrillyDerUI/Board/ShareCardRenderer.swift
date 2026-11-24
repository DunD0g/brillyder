import SwiftUI
import UniformTypeIdentifiers
import BrillyDerCore
#if canImport(UIKit)
import UIKit
import Photos
#elseif canImport(AppKit)
import AppKit
#endif

/// Full configuration describing a BrillyDer Move Highlight Share Card.
public struct BrillyShareCardPayload: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let fen: String
    public let orientation: PieceColor
    public let theme: BoardThemeID
    public let pieceSet: PieceSetID
    public let vibe: VibeMode
    public let calloutStyle: CalloutStyle
    public let emojiPack: BrillyEmojiPack
    public let moveNotation: String?
    public let classification: MoveClassification?
    public let badgeLabelOverride: String?
    public let title: String
    public let coachingLine: String
    public let evalDisplay: String
    public let evalScore: EngineScore?
    public let whiteName: String
    public let blackName: String
    public let whiteAccuracy: Double?
    public let blackAccuracy: Double?
    public let activeSide: PieceColor
    public let accuracyTag: String?
    public let openingName: String?
    public let lastMoveFrom: Square?
    public let lastMoveTo: Square?
    public let showMoveArrow: Bool
    public let quipIndex: Int
    public let customCaption: String?
    public let blurPlayerNames: Bool
    public let exhibitionTheme: CreatorExhibitionTheme
    public let broadcastRibbon: String?
    public let showCreatorHandle: Bool

    public init(
        id: UUID = UUID(),
        fen: String,
        orientation: PieceColor,
        theme: BoardThemeID,
        pieceSet: PieceSetID = .cburnett,
        vibe: VibeMode = .classic,
        calloutStyle: CalloutStyle = .brillyDer,
        emojiPack: BrillyEmojiPack = .mindBlown,
        moveNotation: String? = nil,
        classification: MoveClassification? = nil,
        badgeLabelOverride: String? = nil,
        title: String,
        coachingLine: String = "",
        evalDisplay: String,
        evalScore: EngineScore? = nil,
        whiteName: String = "White",
        blackName: String = "Black",
        whiteAccuracy: Double? = nil,
        blackAccuracy: Double? = nil,
        activeSide: PieceColor = .white,
        accuracyTag: String? = nil,
        openingName: String? = nil,
        lastMove: (from: Square, to: Square)? = nil,
        showMoveArrow: Bool = true,
        quipIndex: Int = 0,
        customCaption: String? = nil,
        blurPlayerNames: Bool = false,
        exhibitionTheme: CreatorExhibitionTheme = .none,
        broadcastRibbon: String? = nil,
        showCreatorHandle: Bool = false
    ) {
        self.id = id
        self.fen = fen
        self.orientation = orientation
        self.theme = theme
        self.pieceSet = pieceSet
        self.vibe = vibe
        self.calloutStyle = calloutStyle
        self.emojiPack = emojiPack
        self.moveNotation = moveNotation
        self.classification = classification
        self.badgeLabelOverride = badgeLabelOverride
        self.title = title
        self.coachingLine = coachingLine
        self.evalDisplay = evalDisplay
        self.evalScore = evalScore
        self.whiteName = whiteName
        self.blackName = blackName
        self.whiteAccuracy = whiteAccuracy
        self.blackAccuracy = blackAccuracy
        self.activeSide = activeSide
        self.accuracyTag = accuracyTag
        self.openingName = openingName
        self.lastMoveFrom = lastMove?.from
        self.lastMoveTo = lastMove?.to
        self.showMoveArrow = showMoveArrow
        self.quipIndex = quipIndex
        self.customCaption = customCaption
        self.blurPlayerNames = blurPlayerNames
        self.exhibitionTheme = exhibitionTheme
        self.broadcastRibbon = broadcastRibbon
        self.showCreatorHandle = showCreatorHandle
    }

    public var lastMove: (from: Square, to: Square)? {
        guard let f = lastMoveFrom, let t = lastMoveTo else { return nil }
        return (f, t)
    }

    public var alienMood: BrillyAlienMood {
        BrillyAlienMood.from(classification: classification)
    }

    public var effectiveCalloutStyle: CalloutStyle {
        calloutStyle
    }

    public func withOverrides(
        vibe: VibeMode,
        calloutStyle: CalloutStyle,
        showMoveArrow: Bool,
        quipIndex: Int,
        customCaption: String? = nil
    ) -> BrillyShareCardPayload {
        BrillyShareCardPayload(
            id: id,
            fen: fen,
            orientation: orientation,
            theme: theme,
            pieceSet: pieceSet,
            vibe: vibe,
            calloutStyle: calloutStyle,
            emojiPack: emojiPack,
            moveNotation: moveNotation,
            classification: classification,
            badgeLabelOverride: badgeLabelOverride,
            title: title,
            coachingLine: coachingLine,
            evalDisplay: evalDisplay,
            evalScore: evalScore,
            whiteName: whiteName,
            blackName: blackName,
            whiteAccuracy: whiteAccuracy,
            blackAccuracy: blackAccuracy,
            activeSide: activeSide,
            accuracyTag: accuracyTag,
            openingName: openingName,
            lastMove: lastMove,
            showMoveArrow: showMoveArrow,
            quipIndex: quipIndex,
            customCaption: customCaption,
            blurPlayerNames: blurPlayerNames,
            exhibitionTheme: exhibitionTheme,
            broadcastRibbon: broadcastRibbon,
            showCreatorHandle: showCreatorHandle
        )
    }
}

/// Lazy `Transferable` wrapper for BrillyDer move share cards:
/// Defers `ImageRenderer` rasterization until the user actually invokes the Share Sheet, keeping 120Hz scrolling smooth.
public struct BrillyShareCardItem: Transferable, Sendable {
    public let payload: BrillyShareCardPayload

    public var title: String {
        if let move = payload.moveNotation, !move.isEmpty {
            let sym = payload.classification?.symbol ?? ""
            return sym.isEmpty ? "\(move) · \(payload.title)" : "\(move)\(sym) · \(payload.title)"
        }
        return payload.title
    }

    public init(payload: BrillyShareCardPayload) {
        self.payload = payload
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            await MainActor.run {
                item.renderPNGData()
            }
        }
    }

    @MainActor
    public func renderPNGData(scale: CGFloat = 3.0) -> Data {
        let card = BrillyShareCardView(payload: payload)
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
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

    #if canImport(UIKit)
    @MainActor
    public func renderUIImage(scale: CGFloat = 3.0) -> UIImage? {
        let card = BrillyShareCardView(payload: payload)
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        return renderer.uiImage
    }
    #endif
}

/// Show-stopping social-ready BrillyDer Move Highlight Card with Alien UFO mascot,
/// glowing move trajectory arrow, origin launch ring, on-board classification badge,
/// integrated eval bar, and matchup summary.
public struct BrillyShareCardView: View {
    public let payload: BrillyShareCardPayload

    public init(payload: BrillyShareCardPayload) {
        self.payload = payload
    }

    private var board: ChessBoard {
        (try? ChessBoard(fen: payload.fen)) ?? ChessBoard()
    }

    private var mood: BrillyAlienMood {
        payload.alienMood
    }

    private var accentColor: Color {
        if let cls = payload.classification {
            return BrillyPalette.color(for: cls)
        }
        return mood.accentColor
    }

    private var badgeInk: Color {
        if let cls = payload.classification {
            return BrillyPalette.badgeForeground(for: cls)
        }
        return Color(hex: 0x070B14)
    }

    private var signalPillText: String {
        if let override = payload.badgeLabelOverride, !override.isEmpty {
            return override.uppercased()
        }
        switch payload.effectiveCalloutStyle {
        case .brillyDer:   return mood.brillyDerTag
        case .cosmicAlien: return mood.cosmicTag
        case .standard:    return mood.classicTag
        }
    }

    private var classificationPillText: String? {
        guard let cls = payload.classification else {
            return payload.badgeLabelOverride
        }
        if cls == .book || cls == .best {
            return cls.label.uppercased()
        }
        if payload.effectiveCalloutStyle == .brillyDer {
            switch cls {
            case .brilliant:  return "!! BRILLY"
            case .blunder:    return "?? BLUN-DER"
            case .mistake:    return "? MINI-DER"
            case .inaccuracy: return "?! SLIP"
            case .great:      return "! GREAT"
            default:          return "\(cls.symbol) \(cls.label.uppercased())"
            }
        }
        return "\(cls.symbol) \(cls.label.uppercased())"
    }

    private var heroQuip: String {
        if let custom = payload.customCaption?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return BrillyShareQuips.quip(for: mood, vibe: payload.vibe, calloutStyle: payload.calloutStyle, index: payload.quipIndex)
    }

    private var normalizedCoaching: String? {
        let trimmed = payload.coachingLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != heroQuip.lowercased() else { return nil }
        return trimmed
    }

    public var body: some View {
        let cardWidth: CGFloat = 400
        let boardSide: CGFloat = 356

        ZStack {
            // 1. Deep Cosmic Void + Procedural Starfield + Classification Nebula Blooms
            cosmicCardBackdrop

            // 2. Card Content Stack
            VStack(spacing: 12) {
                // Optional Exhibition / Broadcast Ribbon (Founder Admin Creator Studio)
                if let ribbon = payload.broadcastRibbon, !ribbon.isEmpty, payload.exhibitionTheme != .none {
                    HStack(spacing: 6) {
                        Image(systemName: payload.exhibitionTheme == .worldChampionship ? "crown.fill" : "bolt.fill")
                            .font(.system(size: 9.5, weight: .black))
                        Text(ribbon)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.3)
                            .lineLimit(1)
                    }
                    .foregroundStyle(BrillyPalette.voidBg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [payload.exhibitionTheme.accentColor, payload.exhibitionTheme.secondaryAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                }

                // Top Brand & Signal Strip
                topBrandHeader

                // Hero Move Notation + Alien UFO Reaction Banner
                heroReactionBanner

                // Framed Chessboard with Move Trajectory Arrow, Origin Launch Ring & On-Board Badge
                boardShowcase(side: boardSide)

                // Integrated Advantage Eval Bar + Coordinate Move Chip
                evalAndMoveStrip

                // Player Matchup, Coaching Insight & Colophon
                footerMatchupBlock
            }
            .padding(20)
        }
        .frame(width: cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: payload.exhibitionTheme != .none
                            ? [payload.exhibitionTheme.accentColor.opacity(0.90), payload.exhibitionTheme.secondaryAccent.opacity(0.70), payload.exhibitionTheme.accentColor.opacity(0.65)]
                            : [accentColor.opacity(0.70), Color.white.opacity(0.22), mood.secondaryGlow.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: payload.exhibitionTheme != .none ? 2.2 : 1.6
                )
        )
    }

    // MARK: - 1. Cosmic Backdrop

    private var cosmicCardBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x060A14), Color(hex: 0x0E182D), Color(hex: 0x070B14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Nebula Glows (classification-tuned!)
            RadialGradient(
                colors: [accentColor.opacity(0.30), accentColor.opacity(0.0)],
                center: UnitPoint(x: 0.86, y: 0.14),
                startRadius: 10,
                endRadius: 210
            )
            RadialGradient(
                colors: [mood.secondaryGlow.opacity(0.22), mood.secondaryGlow.opacity(0.0)],
                center: UnitPoint(x: 0.12, y: 0.90),
                startRadius: 10,
                endRadius: 210
            )

            // Deterministic Crisp Starfield (Cosmic / Alien themes)
            if payload.calloutStyle == .cosmicAlien || payload.vibe == .cosmic {
                Canvas { ctx, size in
                    let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
                        (0.06, 0.02, 1.2, 0.65), (0.39, 0.03, 1.0, 0.50), (0.48, 0.06, 1.3, 0.60),
                        (0.03, 0.14, 1.1, 0.50), (0.97, 0.13, 1.2, 0.55),
                        (0.03, 0.28, 1.0, 0.45), (0.97, 0.29, 1.1, 0.50),
                        (0.03, 0.50, 1.1, 0.42), (0.97, 0.54, 1.2, 0.48),
                        (0.04, 0.78, 1.0, 0.45), (0.96, 0.76, 1.3, 0.55),
                        (0.08, 0.98, 1.1, 0.48), (0.46, 0.98, 1.0, 0.42), (0.86, 0.98, 1.2, 0.52),
                    ]
                    for (nx, ny, r, alpha) in stars {
                        let x = nx * size.width
                        let y = ny * size.height
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(Color.white.opacity(alpha))
                        )
                    }
                }
            }
        }
    }

    // MARK: - 2. Brand & Signal Strip

    private var topBrandHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                BrillyLogoMark(size: 24, circular: true)
                BrillyWordmarkView(fontSize: 13.5, uppercase: true, showSlash: true, tracking: 1.4)
            }

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                Text(signalPillText)
                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(accentColor.opacity(0.14))
                    .overlay(Capsule().strokeBorder(accentColor.opacity(0.42), lineWidth: 1))
            )
        }
    }

    // MARK: - 3. Hero Move & Alien Mascot Banner

    private var heroReactionBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                // Big Bold Move Notation + Classification Pill
                HStack(alignment: .center, spacing: 8) {
                    Text(payload.moveNotation ?? payload.title)
                        .font(.system(size: payload.moveNotation != nil ? 26 : 19, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let pill = classificationPillText {
                        HStack(spacing: 3) {
                            if payload.classification == .book {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 9.5, weight: .bold))
                            } else if payload.classification == .best {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            Text(pill)
                                .font(.system(size: 10.5, weight: .black, design: .rounded))
                                .tracking(0.4)
                        }
                        .foregroundStyle(badgeInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(accentColor)
                                .shadow(color: accentColor.opacity(0.48), radius: 6, y: 1)
                        )
                        .fixedSize()
                    }
                }

                // Witty Brilly/Der, Alien, or Classic Reaction Quote
                Text(payload.calloutStyle == .standard ? heroQuip : "“\(heroQuip)”")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xE2E8F0))
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)

                // Compact Move Trajectory + Accuracy Meta Pills
                HStack(spacing: 6) {
                    if let move = payload.lastMove {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9.5, weight: .black))
                            Text("\(move.from.algebraic) → \(move.to.algebraic)")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(accentColor.opacity(0.15))
                        )
                    }

                    if let acc = payload.accuracyTag, !acc.isEmpty {
                        Text(acc)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(BrillyPalette.inkSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Theme-matched Mascot: Ghibli Thumbs-Up Buddy (Brilly/Der), Diamond Medallion (Standard), or Alien UFO
            switch payload.calloutStyle {
            case .brillyDer:
                BrillyGhibliBuddyView(mood: mood, size: 84, emojiPack: payload.emojiPack)
            case .cosmicAlien:
                BrillyAlienUFOView(mood: mood, size: 86, showBeam: true)
                    .shadow(color: accentColor.opacity(0.42), radius: 10, y: 2)
            case .standard:
                classicHeroMedallion
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.14),
                            Color(hex: 0x0F172A).opacity(0.82),
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accentColor.opacity(0.32), lineWidth: 1)
        )
    }

    private var classicHeroMedallion: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.16))
                .frame(width: 64, height: 64)
            Circle()
                .strokeBorder(accentColor.opacity(0.55), lineWidth: 1.5)
                .frame(width: 64, height: 64)
            if payload.classification == .brilliant || payload.classification == nil {
                BrillyGemIcon(size: 32, color: accentColor)
            } else if payload.classification == .book {
                Image(systemName: "book.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(accentColor)
            } else if payload.classification == .best {
                Image(systemName: "star.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(accentColor)
            } else {
                Text(payload.classification?.symbol ?? "!")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(accentColor)
            }
        }
    }

    // MARK: - 4. Chessboard + Glowing Move Trajectory + On-Board Badge

    @ViewBuilder
    private func boardShowcase(side: CGFloat) -> some View {
        let sqSize = side / 8.0

        ZStack(alignment: .topLeading) {
            // Base High-Res Retina Chessboard (we draw our bespoke Move Arrow + Badge cleanly on top)
            InteractiveChessBoardView(
                board: board,
                orientation: payload.orientation,
                theme: payload.theme,
                surfaceStyle: .cosmic,
                interactive: false,
                lastMove: payload.lastMove,
                moveBadge: nil
            )
            .environment(\.brillyPieceSet, payload.pieceSet)
            .frame(width: side, height: side)

            // Glowing Launch Ring (from) + Destination Aura Frame (to) + Vector Trajectory Arrow
            if let move = payload.lastMove {
                Canvas { ctx, size in
                    let cell = size.width / 8.0
                    let fromRect = squareRect(for: move.from, sqSize: cell)
                    let toRect = squareRect(for: move.to, sqSize: cell)
                    let fromCenter = CGPoint(x: fromRect.midX, y: fromRect.midY)
                    let toCenter = CGPoint(x: toRect.midX, y: toRect.midY)

                    // 1. Origin Launch Pulse Ring on `from` square
                    let ringInset = cell * 0.20
                    let ringPath = Path(ellipseIn: fromRect.insetBy(dx: ringInset, dy: ringInset))
                    ctx.stroke(
                        ringPath,
                        with: .color(Color(hex: 0x070B14).opacity(0.45)),
                        style: StrokeStyle(lineWidth: 4.5, dash: [5, 4])
                    )
                    ctx.stroke(
                        ringPath,
                        with: .color(accentColor.opacity(0.92)),
                        style: StrokeStyle(lineWidth: 2.4, dash: [5, 4])
                    )

                    // 2. Destination Highlight Glow Border on `to` square
                    let destPath = Path(roundedRect: toRect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 5)
                    ctx.stroke(destPath, with: .color(accentColor.opacity(0.95)), lineWidth: 2.6)

                    // 3. Glowing Move Trajectory Arrow (`from` -> stops cleanly at edge of piece on `to`)
                    if payload.showMoveArrow {
                        drawMoveTrajectoryArrow(
                            in: &ctx,
                            from: fromCenter,
                            to: toCenter,
                            cellSize: cell,
                            color: accentColor
                        )
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
            }

            // 4. Gleaming On-Board Classification Badge pinned neatly inside the destination square
            if let cls = payload.classification, let toSq = payload.lastMoveTo {
                let corner = topRightCorner(for: toSq, sqSize: sqSize)
                let badgeSize = max(21, sqSize * 0.44)
                let fg = BrillyPalette.badgeForeground(for: cls)

                ZStack {
                    Circle()
                        .fill(BrillyPalette.color(for: cls))
                    if cls == .book {
                        Image(systemName: "book.fill")
                            .font(.system(size: badgeSize * 0.48, weight: .bold))
                            .foregroundStyle(fg)
                    } else if cls == .best {
                        Image(systemName: "star.fill")
                            .font(.system(size: badgeSize * 0.48, weight: .bold))
                            .foregroundStyle(fg)
                    } else {
                        Text(cls.symbol)
                            .font(.system(size: badgeSize * 0.54, weight: .black, design: .rounded))
                            .foregroundStyle(fg)
                    }
                }
                .frame(width: badgeSize, height: badgeSize)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.88), lineWidth: 1.4))
                .shadow(color: BrillyPalette.color(for: cls).opacity(0.75), radius: 5, y: 0)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .position(x: corner.x - badgeSize * 0.50, y: corner.y + badgeSize * 0.50)
                .allowsHitTesting(false)
            }
        }
        .frame(width: side, height: side)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accentColor.opacity(0.48), lineWidth: 1.4)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 14, y: 6)
        .shadow(color: accentColor.opacity(0.18), radius: 16, y: 0)
    }

    // MARK: - 5. Integrated Eval Bar Strip

    private var evalAndMoveStrip: some View {
        let whiteFraction: CGFloat = {
            if let score = payload.evalScore {
                return CGFloat(ChessMath.clamp(score.winPercentWhite / 100.0, min: 0.05, max: 0.95))
            }
            return payload.activeSide == .white ? 0.72 : 0.28
        }()
        let leftFraction = payload.orientation == .white ? whiteFraction : (1.0 - whiteFraction)
        let leftColor: Color = payload.orientation == .white ? Color(hex: 0xF1F5F9) : Color(hex: 0x1E293B)
        let rightColor: Color = payload.orientation == .white ? Color(hex: 0x1E293B) : Color(hex: 0xF1F5F9)

        return HStack(spacing: 10) {
            // Sleek horizontal advantage bar
            ZStack {
                HStack(spacing: 0) {
                    leftColor.frame(width: 248 * leftFraction)
                    rightColor
                }
                Rectangle()
                    .fill(accentColor.opacity(0.75))
                    .frame(width: 1.5, height: 12)
            }
            .frame(width: 248, height: 12)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Text("EVAL")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                Text(payload.evalDisplay)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(accentColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay(Capsule().strokeBorder(accentColor.opacity(0.32), lineWidth: 1))
            )
        }
    }

    // MARK: - 6. Matchup & Coaching Footer

    private var footerMatchupBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Player Matchup Strip with Accuracy Comparison
            HStack(spacing: 6) {
                playerTag(
                    name: payload.whiteName,
                    accuracy: payload.whiteAccuracy,
                    isWhite: true,
                    highlighted: payload.activeSide == .white
                )
                Text("vs")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                playerTag(
                    name: payload.blackName,
                    accuracy: payload.blackAccuracy,
                    isWhite: false,
                    highlighted: payload.activeSide == .black
                )
                Spacer(minLength: 0)
            }

            // Coaching explanation (wrapped cleanly up to 2 lines — never clipped!)
            if let note = normalizedCoaching {
                Text(note)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0xCBD5E1))
                    .lineSpacing(1.5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Viral Social Colophon Strip (`Analyzed with Brilly/Der` footer pill!)
            HStack(spacing: 6) {
                if let opening = payload.openingName, !opening.isEmpty {
                    Text(opening)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    BrillyLogoMark(size: 13, circular: true)
                    Text("Analyzed with")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                    BrillyWordmarkView(fontSize: 10, uppercase: false, showSlash: true, tracking: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay(Capsule().strokeBorder(BrillyPalette.brillyTeal.opacity(0.28), lineWidth: 0.8))
                )

                if payload.showCreatorHandle {
                    Text("@brillyder")
                        .font(.system(size: 9.5, weight: .black, design: .rounded))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(BrillyPalette.brillyTeal.opacity(0.14))
                                .overlay(Capsule().strokeBorder(BrillyPalette.brillyTeal.opacity(0.35), lineWidth: 0.8))
                        )
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func playerTag(name: String, accuracy: Double?, isWhite: Bool, highlighted: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isWhite ? Color(hex: 0xF8FAFC) : Color(hex: 0x1E293B))
                .frame(width: 9, height: 9)
                .overlay(
                    Circle().strokeBorder(
                        isWhite ? Color.black.opacity(0.35) : Color.white.opacity(0.55),
                        lineWidth: 1
                    )
                )
            Text(name)
                .font(.system(size: 11.5, weight: highlighted ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(highlighted ? .white : BrillyPalette.inkSecondary)
                .lineLimit(1)
                .blur(radius: payload.blurPlayerNames ? 5 : 0)
            if let acc = accuracy {
                Text("\(String(format: "%.1f", acc))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(highlighted ? accentColor : BrillyPalette.inkSecondary.opacity(0.85))
            }
        }
        .padding(.horizontal, highlighted ? 8 : 4)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(highlighted ? accentColor.opacity(0.18) : Color.clear)
        )
    }

    // MARK: - Board Geometry & Trajectory Arrow

    private func squareRect(for sq: Square, sqSize: CGFloat) -> CGRect {
        let col = payload.orientation == .white ? sq.file : (7 - sq.file)
        let row = payload.orientation == .white ? (7 - sq.rank) : sq.rank
        return CGRect(x: CGFloat(col) * sqSize, y: CGFloat(row) * sqSize, width: sqSize, height: sqSize)
    }

    private func topRightCorner(for sq: Square, sqSize: CGFloat) -> CGPoint {
        let col = payload.orientation == .white ? sq.file : (7 - sq.file)
        let row = payload.orientation == .white ? (7 - sq.rank) : sq.rank
        return CGPoint(x: CGFloat(col + 1) * sqSize, y: CGFloat(row) * sqSize)
    }

    private func drawMoveTrajectoryArrow(
        in ctx: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        cellSize: CGFloat,
        color: Color
    ) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let rawLen = hypot(dx, dy)
        guard rawLen > 2 else { return }
        let ux = dx / rawLen
        let uy = dy / rawLen
        let perpX = -uy
        let perpY = ux

        // Launch cleanly from the outer rim of the origin ring and stop just shy of the destination
        // piece's core so both the piece silhouette and the `!!` badge stay 100% readable!
        let startInset = min(rawLen * 0.22, cellSize * 0.26)
        let endInset = min(rawLen * 0.34, cellSize * 0.30)
        let startPt = CGPoint(x: from.x + ux * startInset, y: from.y + uy * startInset)
        let tipPt = CGPoint(x: to.x - ux * endInset, y: to.y - uy * endInset)
        let len = hypot(tipPt.x - startPt.x, tipPt.y - startPt.y)
        guard len > 4 else { return }

        let halfShaft = cellSize * 0.088
        let headLen = min(len * 0.56, cellSize * 0.38)
        let headHalfWidth = cellSize * 0.25
        let neck = CGPoint(x: tipPt.x - ux * headLen, y: tipPt.y - uy * headLen)

        var arrow = Path()
        arrow.move(to: CGPoint(x: startPt.x + perpX * halfShaft, y: startPt.y + perpY * halfShaft))
        arrow.addLine(to: CGPoint(x: neck.x + perpX * halfShaft, y: neck.y + perpY * halfShaft))
        arrow.addLine(to: CGPoint(x: neck.x + perpX * headHalfWidth, y: neck.y + perpY * headHalfWidth))
        arrow.addLine(to: tipPt)
        arrow.addLine(to: CGPoint(x: neck.x - perpX * headHalfWidth, y: neck.y - perpY * headHalfWidth))
        arrow.addLine(to: CGPoint(x: neck.x - perpX * halfShaft, y: neck.y - perpY * halfShaft))
        arrow.addLine(to: CGPoint(x: startPt.x - perpX * halfShaft, y: startPt.y - perpY * halfShaft))
        arrow.closeSubpath()

        // Dark rim shadow so the glowing trajectory arrow pops on BOTH light and dark board themes
        ctx.stroke(arrow, with: .color(Color(hex: 0x070B14).opacity(0.72)), style: StrokeStyle(lineWidth: 3.4, lineJoin: .round))

        // Luminous gradient fill from origin to tip
        ctx.fill(
            arrow,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.72), color.opacity(0.96), Color.white.opacity(0.92)]),
                startPoint: startPt,
                endPoint: tipPt
            )
        )

        // Bright specular rim
        ctx.stroke(arrow, with: .color(Color.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.0, lineJoin: .round))
    }
}

// MARK: - Interactive Share Card Studio Sheet

/// Live preview & export studio sheet for BrillyDer Share Cards:
/// lets users admire the card, toggle Cosmic Alien / Classic style, shuffle witty alien quotes,
/// toggle the move arrow, save straight to Photos, or share via the iOS Share Sheet.
public struct BrillyShareCardSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let basePayload: BrillyShareCardPayload
    let surfaceStyle: SurfaceStyle

    @State private var vibe: VibeMode
    @State private var calloutStyle: CalloutStyle
    @State private var showMoveArrow: Bool
    @State private var quipIndex: Int
    @State private var customCaption: String
    @State private var showingCaptionField: Bool = false
    @State private var showingProPaywall: Bool = false
    @State private var saveNotice: String? = nil
    @State private var saveFailed: Bool = false
    @State private var containerWidth: CGFloat = 390
    @State private var naturalCardHeight: CGFloat = 620

    public init(payload: BrillyShareCardPayload, surfaceStyle: SurfaceStyle = .liquidGlass) {
        self.basePayload = payload
        self.surfaceStyle = surfaceStyle
        _vibe = State(initialValue: payload.vibe)
        _calloutStyle = State(initialValue: payload.calloutStyle)
        _showMoveArrow = State(initialValue: payload.showMoveArrow)
        _quipIndex = State(initialValue: payload.quipIndex)
        _customCaption = State(initialValue: payload.customCaption ?? "")
    }

    private var activePayload: BrillyShareCardPayload {
        let effectiveCaption: String? = store.hasProAccess ? customCaption : nil
        return basePayload.withOverrides(
            vibe: vibe,
            calloutStyle: calloutStyle,
            showMoveArrow: showMoveArrow,
            quipIndex: quipIndex,
            customCaption: effectiveCaption
        )
    }

    private var shareItem: BrillyShareCardItem {
        BrillyShareCardItem(payload: activePayload)
    }

    private var previewScale: CGFloat {
        let available = max(280, containerWidth - 28)
        return min(1.0, available / 400.0)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: surfaceStyle)

                ScrollView {
                    VStack(spacing: 14) {
                        // Live Full-Fidelity Card Preview scaled cleanly to exact container width & height
                        BrillyShareCardView(payload: activePayload)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { newHeight in
                                if newHeight > 100 { naturalCardHeight = newHeight }
                            }
                            .scaleEffect(previewScale, anchor: .top)
                            .frame(width: 400 * previewScale, height: naturalCardHeight * previewScale, alignment: .top)
                            .padding(.top, 4)

                        // Quick Customizers Row
                        HStack(spacing: 8) {
                            Button {
                                switch calloutStyle {
                                case .brillyDer:
                                    calloutStyle = .standard
                                    vibe = .classic
                                case .standard:
                                    calloutStyle = .cosmicAlien
                                    vibe = .cosmic
                                case .cosmicAlien:
                                    calloutStyle = .brillyDer
                                    vibe = .classic
                                }
                            } label: {
                                let styleTitle: String = calloutStyle.title
                                let styleIcon: String = {
                                    switch calloutStyle {
                                    case .brillyDer: return "hand.thumbsup.fill"
                                    case .standard: return "diamond.fill"
                                    case .cosmicAlien: return "sparkles"
                                    }
                                }()
                                Label(styleTitle, systemImage: styleIcon)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(calloutStyle == .standard ? BrillyPalette.inkPrimary : BrillyPalette.brillyTeal)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .brillyGlassPill(surfaceStyle, tint: calloutStyle == .cosmicAlien ? BrillyPalette.warpPurple : (calloutStyle == .brillyDer ? BrillyPalette.brillyTeal : BrillyPalette.goldAmber))
                            }
                            .buttonStyle(.plain)

                            Button {
                                quipIndex += 1
                            } label: {
                                Label("New Quip", systemImage: "shuffle")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .brillyGlassPill(surfaceStyle, tint: BrillyPalette.warpPurple)
                            }
                            .buttonStyle(.plain)

                            if basePayload.lastMove != nil {
                                Button {
                                    showMoveArrow.toggle()
                                } label: {
                                    Label("Arrow", systemImage: showMoveArrow ? "arrow.up.right.circle.fill" : "arrow.up.right.circle")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(showMoveArrow ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .brillyGlassPill(surfaceStyle, tint: showMoveArrow ? BrillyPalette.brillyTeal : Color.white.opacity(0.18))
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                if !store.hasProAccess {
                                    showingProPaywall = true
                                    return
                                }
                                withAnimation(.snappy(duration: 0.2)) {
                                    showingCaptionField.toggle()
                                }
                            } label: {
                                Label(
                                    store.hasProAccess ? "Caption" : "Caption",
                                    systemImage: store.hasProAccess ? "pencil.line" : "lock.fill"
                                )
                                .font(.caption.weight(.bold))
                                .foregroundStyle(
                                    showingCaptionField && store.hasProAccess
                                        ? BrillyPalette.voidBg
                                        : (store.hasProAccess ? BrillyPalette.inkPrimary : BrillyPalette.warpPurpleText)
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Group {
                                        if showingCaptionField && store.hasProAccess {
                                            Capsule().fill(BrillyPalette.brillyTeal)
                                        } else {
                                            Capsule().fill(Color.clear)
                                                .brillyGlassPill(surfaceStyle, tint: BrillyPalette.warpPurple)
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)

                        if showingCaptionField && store.hasProAccess {
                            HStack(spacing: 8) {
                                TextField("Write your own Share Card caption…", text: $customCaption)
                                    .textFieldStyle(.plain)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                if !customCaption.isEmpty {
                                    Button {
                                        customCaption = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .brillySurface(surfaceStyle, cornerRadius: 14, tint: BrillyPalette.brillyTeal)
                            .padding(.horizontal, 16)
                        }

                        // Primary Share & Save to Photos Actions
                        HStack(spacing: 10) {
                            ShareLink(
                                item: shareItem,
                                preview: SharePreview(shareItem.title)
                            ) {
                                Label("Share Card", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.voidBg)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Capsule().fill(BrillyPalette.brillyTeal))
                            }

                            #if canImport(UIKit)
                            Button {
                                saveCardToPhotos()
                            } label: {
                                Label("Save Photo", systemImage: "photo.badge.arrow.down")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .brillyGlassPill(surfaceStyle, tint: BrillyPalette.warpPurple)
                            }
                            .buttonStyle(.plain)
                            #endif
                        }
                        .padding(.horizontal, 16)

                        if let saveNotice {
                            Label(saveNotice, systemImage: saveFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(saveFailed ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill((saveFailed ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal).opacity(0.14))
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                if newWidth > 200 { containerWidth = newWidth }
            }
            .navigationTitle("Move Share Card")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showingProPaywall) {
                BrillyProPaywallSheet(highlightedFeature: "Custom Share Card Captions & Emoji Packs")
                    .environment(store)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    #if canImport(UIKit)
    @MainActor
    private func saveCardToPhotos() {
        let pngData = shareItem.renderPNGData(scale: 3.0)
        guard !pngData.isEmpty else {
            saveFailed = true
            saveNotice = "Could not render card image."
            return
        }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                saveFailed = true
                saveNotice = "Photos access denied — enable Add Photos in Settings > BrillyDer, or tap Share Card."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCreationRequest.forAsset()
                    req.addResource(with: .photo, data: pngData, options: nil)
                }
                saveFailed = false
                saveNotice = "Saved high-res card to Photos!"
                store.notePositiveMilestoneForReview(.shareCardExported)
            } catch {
                saveFailed = true
                saveNotice = "Could not save photo — try Share Card instead."
            }
        }
    }
    #endif
}
