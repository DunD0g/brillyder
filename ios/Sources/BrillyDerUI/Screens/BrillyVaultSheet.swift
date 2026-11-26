import SwiftUI
import BrillyDerCore

public enum VaultTab: String, CaseIterable, Identifiable, Sendable {
    case brilliant = "!! Brilliant"
    case clutch = "Clutch"
    case traps = "Traps"
    case sweeps = "Sweeps"
    case saved = "Saved"
    public var id: String { rawValue }
}

public struct BrillyVaultSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: VaultTab
    @State private var activeShareCard: BrillyShareCardPayload? = nil
    @State private var selectedTagFilter: String? = nil
    @State private var editingBookmark: SavedPositionBookmark? = nil

    public init(initialTab: VaultTab = .brilliant) {
        _selectedTab = State(initialValue: initialTab)
    }

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
            .sheet(item: $activeShareCard) { payload in
                BrillyShareCardSheet(payload: payload, surfaceStyle: store.surfaceStyle)
            }
            .sheet(item: $editingBookmark) { bm in
                BookmarkEditSheet(bookmark: bm)
                    .environment(store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
                let movePair: (from: Square, to: Square)? = {
                    if let fStr = item.fromSquare, let tStr = item.toSquare,
                       let f = Square(algebraic: fStr), let t = Square(algebraic: tStr) {
                        return (f, t)
                    }
                    return nil
                }()
                let effectiveClass: MoveClassification? = item.classification ?? (item.kind == .brilliant ? .brilliant : nil)
                let thumbBadge: MoveBadgeOverlay? = {
                    if let cls = effectiveClass, let toSq = movePair?.to {
                        return MoveBadgeOverlay(square: toSq, classification: cls)
                    }
                    return nil
                }()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        InteractiveChessBoardView(
                            board: board,
                            orientation: item.color,
                            theme: store.effectiveBoardTheme,
                            surfaceStyle: store.surfaceStyle,
                            interactive: false,
                            lastMove: movePair,
                            moveBadge: thumbBadge
                        )
                        .frame(width: 84, height: 84)

                        let maskedW = store.maskedPlayerName(item.whiteName, opponent: item.blackName, side: .white)
                        let maskedB = store.maskedPlayerName(item.blackName, opponent: item.whiteName, side: .black)
                        let displayTitle: String = {
                            if store.effectiveCreatorNameMask == .off {
                                return item.title
                            }
                            let oppMasked = (item.color == .white ? maskedB.text : maskedW.text)
                            return item.kind == .cleanSweep
                                ? "Clean Sweep vs \(oppMasked)"
                                : "\(item.moveNumber)\(item.color == .white ? "." : "...") \(item.san) vs \(oppMasked)"
                        }()

                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayTitle)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .blur(radius: (maskedW.isBlurred || maskedB.isBlurred) ? 4 : 0)
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

                        Button {
                            let accTag: String? = {
                                if let acc = item.userAccuracy, let elo = item.userEstimatedElo {
                                    return "\(String(format: "%.1f", acc))% · ~\(elo)"
                                }
                                return nil
                            }()
                            let notation: String? = item.kind == .cleanSweep
                                ? nil
                                : "\(item.moveNumber)\(item.color == .white ? "." : "...") \(item.san)"
                            let badgeOverride: String? = {
                                switch item.kind {
                                case .brilliant: return nil
                                case .clutchSave: return "Clutch Save"
                                case .trap: return "Trap Punished"
                                case .cleanSweep: return "Clean Sweep"
                                }
                            }()
                            let maskedW = store.maskedPlayerName(item.whiteName, opponent: item.blackName, side: .white)
                            let maskedB = store.maskedPlayerName(item.blackName, opponent: item.whiteName, side: .black)
                            let matchedPgn = store.analyzedGames.first(where: { $0.id == item.gameId })?.game.pgn
                            activeShareCard = BrillyShareCardPayload(
                                fen: item.fen,
                                orientation: item.color,
                                theme: store.effectiveBoardTheme,
                                pieceSet: store.effectivePieceSet,
                                vibe: store.vibeMode,
                                calloutStyle: store.effectiveCalloutStyle,
                                emojiPack: store.effectiveEmojiPack,
                                moveNotation: notation,
                                classification: effectiveClass,
                                badgeLabelOverride: badgeOverride,
                                title: "\(maskedW.text) vs \(maskedB.text)",
                                coachingLine: item.subtitle,
                                evalDisplay: item.evalDisplay,
                                evalScore: item.evalScore,
                                whiteName: maskedW.text,
                                blackName: maskedB.text,
                                whiteAccuracy: item.whiteAccuracy,
                                blackAccuracy: item.blackAccuracy,
                                activeSide: item.color,
                                accuracyTag: accTag,
                                openingName: item.openingName,
                                lastMove: movePair,
                                showMoveArrow: true,
                                quipIndex: Int.random(in: 0..<12),
                                blurPlayerNames: maskedW.isBlurred || maskedB.isBlurred,
                                exhibitionTheme: store.effectiveExhibitionTheme,
                                broadcastRibbon: store.resolvedBroadcastRibbon(forPgn: matchedPgn),
                                showCreatorHandle: store.effectiveShowCreatorHandle
                            )
                        } label: {
                            Label("Share Card", systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .brillySurface(store.surfaceStyle, cornerRadius: 18)
            }
        }
    }

    @ViewBuilder
    private var bookmarksList: some View {
        let allTags: [String] = {
            var seen = Set<String>()
            var ordered: [String] = []
            for bm in store.bookmarks {
                for tag in bm.tags {
                    let key = tag.lowercased()
                    if seen.insert(key).inserted {
                        ordered.append(tag)
                    }
                }
            }
            return ordered
        }()

        let filteredBookmarks: [SavedPositionBookmark] = {
            guard let tag = selectedTagFilter else { return store.bookmarks }
            let target = tag.lowercased()
            return store.bookmarks.filter { bm in
                bm.tags.contains { $0.lowercased() == target }
            }
        }()

        if store.bookmarks.isEmpty {
            Text("Tap the Bookmark button in Analyze to save key positions here.")
                .font(.subheadline)
                .foregroundStyle(BrillyPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(28)
                .frame(maxWidth: .infinity)
                .brillySurface(store.surfaceStyle, cornerRadius: 18)
        } else {
            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        bookmarkTagFilterChip("All", isSelected: selectedTagFilter == nil) {
                            selectedTagFilter = nil
                        }
                        ForEach(allTags, id: \.self) { tag in
                            let sel = selectedTagFilter?.lowercased() == tag.lowercased()
                            bookmarkTagFilterChip(tag, isSelected: sel) {
                                selectedTagFilter = sel ? nil : tag
                            }
                        }
                    }
                }
            }

            if filteredBookmarks.isEmpty {
                Text("No saved bookmarks match tag \"\(selectedTagFilter ?? "")\".")
                    .font(.caption)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .brillySurface(store.surfaceStyle, cornerRadius: 16)
            } else {
                ForEach(filteredBookmarks) { bm in
                    let maskedMatchup = formattedMaskedMatchup(for: bm)
                    HStack(spacing: 10) {
                        Button {
                            if let ag = store.analyzedGames.first(where: { $0.id == bm.gameId }) {
                                dismiss()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(320))
                                    store.startAnalysis(for: ag.game, jumpToPly: bm.ply, isManualSelection: true, switchToAnalyze: true)
                                }
                            } else if let rec = store.recentGames.first(where: { $0.id == bm.gameId }) {
                                dismiss()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(320))
                                    store.startAnalysis(for: rec, jumpToPly: bm.ply, isManualSelection: true, switchToAnalyze: true)
                                }
                            } else {
                                dismiss()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(320))
                                    store.openCustomFEN(bm.fen)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                InteractiveChessBoardView(
                                    board: (try? ChessBoard(fen: bm.fen)) ?? ChessBoard(),
                                    orientation: bm.color,
                                    theme: store.effectiveBoardTheme,
                                    surfaceStyle: store.surfaceStyle,
                                    interactive: false
                                )
                                .frame(width: 70, height: 70)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bm.label)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)

                                    HStack(spacing: 6) {
                                        if let matchup = maskedMatchup {
                                            Text(matchup.text)
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(BrillyPalette.inkSecondary)
                                                .lineLimit(1)
                                                .blur(radius: matchup.isBlurred ? 5 : 0)
                                        }
                                        if let eval = bm.evalDisplay {
                                            if maskedMatchup != nil {
                                                Text("·")
                                                    .font(.caption2)
                                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                            }
                                            Text("Eval \(eval)")
                                                .font(.caption2.monospacedDigit().weight(.semibold))
                                                .foregroundStyle(BrillyPalette.brillyTeal)
                                        }
                                    }

                                    if !bm.tags.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 5) {
                                                ForEach(bm.tags, id: \.self) { tag in
                                                    let tint = bookmarkTagColor(tag)
                                                    Text(tag)
                                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                                        .foregroundStyle(tint)
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 2.5)
                                                        .background(
                                                            Capsule()
                                                                .fill(tint.opacity(0.16))
                                                                .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.8))
                                                        )
                                                }
                                            }
                                        }
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 4) {
                            Button {
                                editingBookmark = bm
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                    .padding(7)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rename or tag bookmark")

                            Button {
                                store.removeBookmark(id: bm.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                                    .foregroundStyle(BrillyPalette.blunderRose)
                                    .padding(7)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete bookmark")
                        }
                    }
                    .padding(12)
                    .brillySurface(store.surfaceStyle, cornerRadius: 16, interactive: true)
                    .contextMenu {
                        Button {
                            editingBookmark = bm
                        } label: {
                            Label("Rename / Tag", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.removeBookmark(id: bm.id)
                        } label: {
                            Label("Delete Bookmark", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func bookmarkTagFilterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.caption2.weight(.bold))
            .foregroundStyle(isSelected ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isSelected ? BrillyPalette.goldAmber : Color.white.opacity(0.08)))
            .buttonStyle(.plain)
    }

    private func bookmarkTagColor(_ tag: String) -> Color {
        switch tag.lowercased() {
        case "wcc", "tournament": return BrillyPalette.goldAmber
        case "brilliant", "tactic": return BrillyPalette.brillyTeal
        case "endgame": return Color(hex: 0x22C55E)
        case "opening": return BrillyPalette.warpPurpleText
        case "blunder": return BrillyPalette.blunderRose
        default: return BrillyPalette.brillyTeal
        }
    }

    private func formattedMaskedMatchup(for bm: SavedPositionBookmark) -> (text: String, isBlurred: Bool)? {
        let raw: String? = {
            if let m = bm.matchup, !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return m
            }
            if let ag = store.analyzedGames.first(where: { $0.id == bm.gameId }) {
                return "\(ag.game.white.name) vs \(ag.game.black.name)"
            }
            if let rec = store.recentGames.first(where: { $0.id == bm.gameId }) {
                return "\(rec.white.name) vs \(rec.black.name)"
            }
            return nil
        }()
        guard let raw else { return nil }
        guard store.effectiveCreatorNameMask != .off else { return (raw, false) }
        let parts = raw.components(separatedBy: " vs ")
        if parts.count == 2 {
            let w = store.maskedPlayerName(parts[0], opponent: parts[1], side: .white)
            let b = store.maskedPlayerName(parts[1], opponent: parts[0], side: .black)
            return ("\(w.text) vs \(b.text)", w.isBlurred || b.isBlurred)
        }
        let m = store.maskedPlayerName(raw, opponent: nil, side: .white)
        return (m.text, m.isBlurred)
    }
}

// MARK: - Bookmark Rename & Tag Editor Sheet

private struct BookmarkEditSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let bookmark: SavedPositionBookmark

    @State private var labelDraft: String
    @State private var selectedTags: [String]
    @State private var customTagDraft: String = ""

    private let quickTags = ["WCC", "Study", "Opening", "Endgame", "Tactic", "Brilliant"]

    init(bookmark: SavedPositionBookmark) {
        self.bookmark = bookmark
        _labelDraft = State(initialValue: bookmark.label)
        _selectedTags = State(initialValue: bookmark.tags)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BOOKMARK TITLE")
                                .font(.caption2.weight(.bold))
                                .tracking(0.9)
                                .foregroundStyle(BrillyPalette.brillyTeal)

                            TextField("e.g. WCC Game 1 · Critical Sacrifice", text: $labelDraft)
                                .textFieldStyle(.plain)
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("QUICK TAGS")
                                .font(.caption2.weight(.bold))
                                .tracking(0.9)
                                .foregroundStyle(BrillyPalette.brillyTeal)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                                ForEach(quickTags, id: \.self) { tag in
                                    let active = selectedTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                    Button {
                                        toggleTag(tag)
                                    } label: {
                                        HStack(spacing: 4) {
                                            if active {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .black))
                                            }
                                            Text(tag)
                                                .font(.caption.weight(.bold))
                                        }
                                        .foregroundStyle(active ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(active ? BrillyPalette.brillyTeal : Color.white.opacity(0.08))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("CUSTOM TAG")
                                .font(.caption2.weight(.bold))
                                .tracking(0.9)
                                .foregroundStyle(BrillyPalette.inkSecondary)

                            HStack(spacing: 8) {
                                TextField("Add custom tag…", text: $customTagDraft)
                                    .textFieldStyle(.plain)
                                    #if os(iOS)
                                    .submitLabel(.done)
                                    #endif
                                    .onSubmit { addCustomTag() }
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))

                                Button("+ Add") {
                                    addCustomTag()
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.voidBg)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BrillyPalette.goldAmber))
                                .buttonStyle(.plain)
                                .disabled(customTagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            let customOnly = selectedTags.filter { tag in
                                !quickTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                            }
                            if !customOnly.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(customOnly, id: \.self) { tag in
                                            Button {
                                                toggleTag(tag)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Text(tag)
                                                        .font(.caption2.weight(.bold))
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 9, weight: .bold))
                                                }
                                                .foregroundStyle(BrillyPalette.goldAmber)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 5)
                                                .background(Capsule().fill(BrillyPalette.goldAmber.opacity(0.18)))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        Button {
                            store.updateBookmark(id: bookmark.id, label: labelDraft, tags: selectedTags)
                            dismiss()
                        } label: {
                            Text("Save Bookmark")
                                .font(.headline)
                                .foregroundStyle(BrillyPalette.voidBg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 14).fill(BrillyPalette.brillyTeal))
                        }
                        .buttonStyle(.plain)
                        .disabled(labelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Rename & Tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func toggleTag(_ tag: String) {
        if let idx = selectedTags.firstIndex(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            selectedTags.remove(at: idx)
        } else {
            selectedTags.append(tag)
        }
        store.triggerHaptic(.move)
    }

    private func addCustomTag() {
        let cleaned = customTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if !selectedTags.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) {
            selectedTags.append(cleaned)
        }
        customTagDraft = ""
        store.triggerHaptic(.move)
    }
}
