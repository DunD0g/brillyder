import SwiftUI
import BrillyDerCore

public struct AnalyzeTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var currentPlyIndex: Int = 0 // 0 = initial position, 1...plies.count
    @State private var orientation: PieceColor = .white
    @State private var retryMode: Bool = false
    @State private var retryFeedback: String? = nil

    public var body: some View {
        ZStack {
            CosmicVoidBackdrop(style: store.surfaceStyle)

            if store.isAnalyzing {
                VStack(spacing: 16) {
                    ProgressView(value: store.analysisProgress)
                        .tint(BrillyPalette.brillyTeal)
                        .frame(maxWidth: 260)
                    Text(store.analysisStatusText)
                        .font(.headline)
                        .foregroundStyle(BrillyPalette.inkPrimary)
                    Text("Running native on-device \(store.analysisPreset.title) analysis…")
                        .font(.caption)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                    Button("Cancel") {
                        store.cancelAnalysis()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrillyPalette.blunderRose)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.blunderRose)
                    .buttonStyle(.plain)
                }
                .padding(28)
                .brillySurface(store.surfaceStyle, cornerRadius: 24, tint: BrillyPalette.brillyTeal)
                .padding()
            } else if let analyzed = store.activeAnalyzedGame {
                analyzedBody(analyzed)
            } else {
                emptyState
            }
        }
        .navigationTitle("Analyze")
        .onChange(of: store.activeAnalyzedGame?.id) { _, _ in
            if let ag = store.activeAnalyzedGame {
                currentPlyIndex = min(1, ag.plies.count)
                orientation = ag.game.userColor ?? .white
                retryMode = false
                retryFeedback = nil
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(BrillyPalette.brillyTeal)
            Text("Pick a Game to Analyze")
                .font(.title3.weight(.bold))
                .foregroundStyle(BrillyPalette.inkPrimary)
            Text("Sync Lichess or Chess.com, paste a PGN, or try a built-in showcase game.")
                .font(.subheadline)
                .foregroundStyle(BrillyPalette.inkSecondary)
                .multilineTextAlignment(.center)
            if let sample = store.recentGames.first {
                Button("Analyze Showcase Game") {
                    store.startAnalysis(for: sample)
                }
                .font(.headline)
                .foregroundStyle(BrillyPalette.voidBg)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(BrillyPalette.brillyTeal))
                .buttonStyle(.plain)
            }
        }
        .padding(26)
        .brillySurface(store.surfaceStyle, cornerRadius: 24)
        .padding()
    }

    @ViewBuilder
    private func analyzedBody(_ ag: AnalyzedGame) -> some View {
        let clampedPly = max(0, min(currentPlyIndex, ag.plies.count))
        let activePly: AnalyzedPly? = clampedPly > 0 ? ag.plies[clampedPly - 1] : nil
        let fenToShow: String = {
            if retryMode, let ap = activePly { return ap.beforeFen }
            if let ap = activePly { return ap.afterFen }
            return ChessBoard.initialFEN
        }()
        let board = (try? ChessBoard(fen: fenToShow)) ?? ChessBoard()
        let score = activePly?.evalAfter ?? ag.initialEval
        let lastMovePair: (Square, Square)? = {
            guard !retryMode, let ap = activePly,
                  let f = Square(algebraic: ap.from),
                  let t = Square(algebraic: ap.to) else { return nil }
            return (f, t)
        }()
        let badge: MoveBadgeOverlay? = {
            guard !retryMode, let ap = activePly, let sq = Square(algebraic: ap.to) else { return nil }
            return MoveBadgeOverlay(square: sq, classification: ap.classification)
        }()
        let bestArrow: [BoardArrow] = {
            guard !retryMode, let ap = activePly,
                  ap.classification == .blunder || ap.classification == .mistake || ap.classification == .inaccuracy,
                  let m = ChessMove(uci: ap.bestMoveUci) else { return [] }
            return [BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)]
        }()

        ScrollView {
            VStack(spacing: 12) {
                // Accuracy Summary Strip
                HStack(spacing: 10) {
                    playerSummaryPill(name: ag.game.white.name, acc: ag.whiteSummary.accuracy, elo: ag.whiteSummary.estimatedElo, isWhite: true)
                    playerSummaryPill(name: ag.game.black.name, acc: ag.blackSummary.accuracy, elo: ag.blackSummary.estimatedElo, isWhite: false)
                }

                // Eval Bar
                EvalBarView(score: score, orientation: orientation)

                // Interactive Board
                InteractiveChessBoardView(
                    board: board,
                    orientation: orientation,
                    theme: store.boardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: retryMode,
                    lastMove: lastMovePair,
                    arrows: bestArrow,
                    moveBadge: badge
                ) { move in
                    guard retryMode, let ap = activePly else { return }
                    if move.uci == ap.bestMoveUci {
                        retryFeedback = "Nailed it! \(ap.bestMoveSan) was the best move."
                        retryMode = false
                        store.triggerHaptic(.success)
                    } else {
                        retryFeedback = "Not \(move.uci) — keep hunting for a stronger continuation!"
                        store.triggerHaptic(.error)
                    }
                }

                // Transport Scrubber Bar (Grouped in Liquid Glass Cluster)
                BrillyGlassCluster(style: store.surfaceStyle, spacing: 10) {
                    HStack(spacing: 10) {
                        transportBtn("backward.end.fill") { currentPlyIndex = 0; retryMode = false }
                        transportBtn("chevron.left") { currentPlyIndex = max(0, clampedPly - 1); retryMode = false }
                        transportBtn("chevron.right") { currentPlyIndex = min(ag.plies.count, clampedPly + 1); retryMode = false }
                        transportBtn("forward.end.fill") { currentPlyIndex = ag.plies.count; retryMode = false }
                        transportBtn("arrow.up.arrow.down") { orientation = orientation.opposite }
                        if let ap = activePly {
                            let isSaved = store.bookmarks.contains { $0.id == "\(ag.game.id)::ply::\(ap.ply)" }
                            transportBtn(isSaved ? "bookmark.fill" : "bookmark") {
                                store.toggleBookmark(ply: ap, game: ag.game)
                            }
                        }
                    }
                }

                // Coach Card
                if let ap = activePly {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(ap.moveNumber)\(ap.color == .white ? "." : "...") \(ap.san)")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            Text(ap.classification.label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(BrillyPalette.color(for: ap.classification)))
                            Spacer()
                            if ap.classification == .blunder || ap.classification == .mistake {
                                Button(retryMode ? "Exit Retry" : "Retry Mistake") {
                                    retryMode.toggle()
                                    retryFeedback = retryMode ? "Find the better move instead of \(ap.san)." : nil
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                                .buttonStyle(.plain)
                            }
                        }

                        Text(retryFeedback ?? ap.coaching.headline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkPrimary)

                        Text(ap.coaching.detail)
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.inkSecondary)

                        if let lines = ap.topLines, !lines.isEmpty, !retryMode {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(lines.prefix(2).enumerated()), id: \.offset) { idx, line in
                                    HStack(spacing: 6) {
                                        Text("#\(idx + 1)")
                                            .font(.caption2.monospacedDigit().weight(.bold))
                                            .foregroundStyle(BrillyPalette.brillyTeal)
                                        Text(line.evalDisplay)
                                            .font(.caption2.monospacedDigit().weight(.bold))
                                            .foregroundStyle(BrillyPalette.inkPrimary)
                                            .frame(width: 40, alignment: .leading)
                                        Text(line.pvSan.joined(separator: " "))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(14)
                    .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.color(for: ap.classification))
                }

                // Horizontal Move Strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ag.plies) { ply in
                            let selected = ply.ply == clampedPly
                            Button {
                                currentPlyIndex = ply.ply
                                retryMode = false
                                retryFeedback = nil
                            } label: {
                                HStack(spacing: 4) {
                                    if ply.color == .white {
                                        Text("\(ply.moveNumber).")
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                    }
                                    Text(ply.san)
                                        .fontWeight(selected ? .bold : .medium)
                                        .foregroundStyle(selected ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                    if ply.classification == .brilliant || ply.classification == .blunder || ply.classification == .mistake {
                                        Circle()
                                            .fill(BrillyPalette.color(for: ply.classification))
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .font(.caption.monospaced())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func playerSummaryPill(name: String, acc: Double, elo: Int, isWhite: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isWhite ? Color.white : Color(hex: 0x1E293B))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                    .lineLimit(1)
                Text("\(String(format: "%.1f", acc))% · ~\(elo)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BrillyPalette.brillyTeal)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .brillySurface(store.surfaceStyle, cornerRadius: 14)
    }

    private func transportBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            store.triggerHaptic(.move)
            action()
        } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrillyPalette.inkPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .brillySurface(store.surfaceStyle, cornerRadius: 14, interactive: true)
        }
        .buttonStyle(.plain)
    }
}
