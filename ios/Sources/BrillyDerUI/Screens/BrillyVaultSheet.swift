import SwiftUI
import BrillyDerCore

public struct BrillyVaultSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum VaultTab: String, CaseIterable, Identifiable {
        case brilliant = "!! Brilliant"
        case clutch = "Clutch"
        case traps = "Traps"
        case sweeps = "Sweeps"
        case saved = "Saved"
        var id: String { rawValue }
    }

    @State private var selectedTab: VaultTab = .brilliant

    public var body: some View {
        let vault = store.vaultCollection

        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                VStack(spacing: 12) {
                    // Headline Brilliant Counter Banner (strictly user !! moves)
                    HStack(spacing: 12) {
                        BrillyGemIcon(size: 32, color: BrillyPalette.brillyTeal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(vault.headlineBrilliantCount) Brilliant Move\(vault.headlineBrilliantCount == 1 ? "" : "s")")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            Text("Headline count tracks strictly your !! moves · \(vault.clutchSaves.count) clutch · \(store.bookmarks.count) saved")
                                .font(.caption2)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.brillyTeal)
                    .padding(.horizontal, 16)

                    // Category Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(VaultTab.allCases) { tab in
                                let sel = selectedTab == tab
                                Button(tab.rawValue) {
                                    selectedTab = tab
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(sel ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(sel ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Content List
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            switch selectedTab {
                            case .brilliant:
                                highlightList(vault.brilliants, emptyText: "No !! Brilliant moves yet — run Batch Analyze in Games to uncover yours!")
                            case .clutch:
                                highlightList(vault.clutchSaves, emptyText: "No Clutch Saves recorded yet.")
                            case .traps:
                                highlightList(vault.traps, emptyText: "No Opening Traps Punished recorded yet.")
                            case .sweeps:
                                highlightList(vault.cleanSweeps, emptyText: "Win a game with 88%+ accuracy and 0 blunders to earn a Clean Sweep!")
                            case .saved:
                                bookmarksList
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle(store.copy(cosmic: "Brilly Vault", classic: "Trophy Vault"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func highlightList(_ items: [VaultHighlight], emptyText: String) -> some View {
        if items.isEmpty {
            Text(emptyText)
                .font(.subheadline)
                .foregroundStyle(BrillyPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(28)
                .frame(maxWidth: .infinity)
                .brillySurface(store.surfaceStyle, cornerRadius: 18)
        } else {
            ForEach(items) { item in
                let board = (try? ChessBoard(fen: item.fen)) ?? ChessBoard()
                // Lazy Transferable share card — zero ImageRenderer work while scrolling!
                let shareItem = BrillyShareCardItem(
                    fen: item.fen,
                    orientation: item.color,
                    theme: store.boardTheme,
                    pieceSet: store.pieceSet,
                    title: item.title,
                    subtitle: item.subtitle,
                    evalDisplay: item.evalDisplay,
                    badgeText: item.kind == .brilliant ? "!!" : item.kind.title,
                    classification: item.kind == .brilliant ? .brilliant : nil
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        InteractiveChessBoardView(
                            board: board,
                            orientation: item.color,
                            theme: store.boardTheme,
                            surfaceStyle: store.surfaceStyle,
                            interactive: false
                        )
                        .frame(width: 84, height: 84)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                                .lineLimit(2)
                            Text("Eval \(item.evalDisplay)")
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Button {
                            store.openGameAtPly(gameId: item.gameId, ply: item.ply)
                        } label: {
                            Label("Open in Analyze", systemImage: "arrow.up.right.square")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.voidBg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(BrillyPalette.brillyTeal))
                        }
                        .buttonStyle(.plain)

                        ShareLink(item: shareItem, preview: SharePreview(item.title)) {
                            Label("Share Card", systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                        }
                    }
                }
                .padding(14)
                .brillySurface(store.surfaceStyle, cornerRadius: 18)
            }
        }
    }

    @ViewBuilder
    private var bookmarksList: some View {
        if store.bookmarks.isEmpty {
            Text("Tap the Bookmark button in Analyze to save key positions here.")
                .font(.subheadline)
                .foregroundStyle(BrillyPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(28)
                .frame(maxWidth: .infinity)
                .brillySurface(store.surfaceStyle, cornerRadius: 18)
        } else {
            ForEach(store.bookmarks) { bm in
                HStack(spacing: 10) {
                    Button {
                        if store.analyzedGames.contains(where: { $0.id == bm.gameId }) {
                            store.openGameAtPly(gameId: bm.gameId, ply: bm.ply)
                        } else {
                            dismiss()
                            store.openCustomFEN(bm.fen)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            InteractiveChessBoardView(
                                board: (try? ChessBoard(fen: bm.fen)) ?? ChessBoard(),
                                orientation: bm.color,
                                theme: store.boardTheme,
                                surfaceStyle: store.surfaceStyle,
                                interactive: false
                            )
                            .frame(width: 70, height: 70)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(bm.label)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                    .multilineTextAlignment(.leading)
                                if let eval = bm.evalDisplay {
                                    Text("Eval \(eval)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(BrillyPalette.brillyTeal)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.removeBookmark(id: bm.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(BrillyPalette.blunderRose)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete bookmark")
                }
                .padding(12)
                .brillySurface(store.surfaceStyle, cornerRadius: 16, interactive: true)
            }
        }
    }
}
