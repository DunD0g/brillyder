import SwiftUI
import BrillyDerCore

public struct OpeningsTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var sideFilter: RepertoireSide = .white
    @State private var categoryFilter: OpeningCategoryFilter = .all
    @State private var sortOption: OpeningSortOption = .grouped
    @State private var searchQuery: String = ""
    @State private var selectedCourse: OpeningCourse? = nil
    @State private var showingImportSheet: Bool = false

    private enum OpeningCategoryFilter: String, CaseIterable, Identifiable {
        case all
        case daily
        case e4
        case d4
        case gambit
        case custom

        var id: String { rawValue }

        func label(for side: RepertoireSide) -> String {
            switch self {
            case .all:    return "All"
            case .daily:  return "In Daily"
            case .e4:     return side == .white ? "1. e4" : "vs 1. e4"
            case .d4:     return side == .white ? "1. d4 / c4" : "vs 1. d4"
            case .gambit: return "Gambits"
            case .custom: return "Custom"
            }
        }
    }

    private enum OpeningSortOption: String, CaseIterable, Identifiable {
        case grouped = "Grouped"
        case dueFirst = "Due First"
        case lowestRecall = "Lowest Recall"
        case difficulty = "Difficulty"
        case alphabetical = "A–Z"

        var id: String { rawValue }
    }

    private struct CourseGroup: Identifiable {
        let id: String
        let title: String
        let icon: String
        let tint: Color
        let items: [OpeningCourse]
    }

    private var whiteCount: Int {
        store.allCourses.filter { $0.side == .white }.count
    }

    private var blackCount: Int {
        store.allCourses.filter { $0.side == .black }.count
    }

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasCustomForSide: Bool {
        store.allCourses.contains { $0.side == sideFilter && isCustomCourse($0) }
    }

    private var visibleFilterChips: [OpeningCategoryFilter] {
        var chips: [OpeningCategoryFilter] = [.all, .daily, .e4, .d4, .gambit]
        if hasCustomForSide { chips.append(.custom) }
        return chips
    }

    private func isCustomCourse(_ course: OpeningCourse) -> Bool {
        course.source == "pgn" || course.source == "lichess-study"
    }

    private func primaryBucket(for course: OpeningCourse) -> OpeningCategoryFilter {
        if isCustomCourse(course) { return .custom }
        let lowerName = course.name.lowercased()
        let isSharpGambit = (lowerName.contains("gambit") && !lowerName.contains("queen's gambit"))
            || course.difficulty.lowercased() == "aggressive"
        if isSharpGambit { return .gambit }
        let firstMove = course.lines.first?.moves.first ?? course.mothershipSetup.previewMoves.first ?? ""
        if firstMove == "e4" { return .e4 }
        return .d4
    }

    private func dueCount(for course: OpeningCourse) -> Int {
        store.fsrsCards.filter { $0.courseId == course.id && FSRS6Scheduler.isCardDue($0) }.count
    }

    private func avgRecall(for course: OpeningCourse) -> Int {
        let reviewed = store.fsrsCards.filter { $0.courseId == course.id && $0.attempts > 0 }
        guard !reviewed.isEmpty else { return -1 }
        return reviewed.map { FSRS6Scheduler.recallProbability(for: $0) }.reduce(0, +) / reviewed.count
    }

    private func difficultyRank(_ difficulty: String) -> Int {
        switch difficulty.lowercased() {
        case "beginner": return 0
        case "intermediate": return 1
        case "aggressive": return 2
        default: return 3
        }
    }

    private var courses: [OpeningCourse] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [OpeningCourse]
        if !q.isEmpty {
            // Search across BOTH White & Black courses so typing "QGD", "Ruy Lopez", or "Caro-Kann" always finds them!
            base = store.allCourses.filter { c in
                c.name.lowercased().contains(q)
                    || c.tagline.lowercased().contains(q)
                    || c.codename.lowercased().contains(q)
                    || c.lines.contains(where: { $0.title.lowercased().contains(q) || $0.eco.lowercased().contains(q) })
                    || (c.counterGuide?.contains(where: { $0.title.lowercased().contains(q) }) ?? false)
            }
        } else {
            base = store.allCourses.filter { c in
                guard c.side == sideFilter else { return false }
                switch categoryFilter {
                case .all:    return true
                case .daily:  return store.isCourseInDaily(c.id)
                case .custom: return isCustomCourse(c)
                case .e4, .d4, .gambit:
                    return primaryBucket(for: c) == categoryFilter
                }
            }
        }

        switch sortOption {
        case .grouped:
            return base
        case .dueFirst:
            return base.sorted { a, b in
                let da = dueCount(for: a), db = dueCount(for: b)
                if da != db { return da > db }
                return a.name < b.name
            }
        case .lowestRecall:
            return base.sorted { a, b in
                let ra = avgRecall(for: a), rb = avgRecall(for: b)
                if ra != rb { return ra < rb }
                return a.name < b.name
            }
        case .difficulty:
            return base.sorted { a, b in
                let da = difficultyRank(a.difficulty), db = difficultyRank(b.difficulty)
                if da != db { return da < db }
                return a.name < b.name
            }
        case .alphabetical:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var groupedCourses: [CourseGroup] {
        let list = courses
        guard !isSearching && sortOption == .grouped && categoryFilter == .all else { return [] }

        var groups: [CourseGroup] = []
        let dailyItems = list.filter { store.isCourseInDaily($0.id) }
        let dailyIds = Set(dailyItems.map(\.id))
        if !dailyItems.isEmpty {
            groups.append(CourseGroup(
                id: "daily",
                title: "Pinned in Daily FSRS",
                icon: "bolt.circle.fill",
                tint: BrillyPalette.brillyTeal,
                items: dailyItems
            ))
        }

        let remaining = list.filter { !dailyIds.contains($0.id) }
        let e4Items = remaining.filter { primaryBucket(for: $0) == .e4 }
        let d4Items = remaining.filter { primaryBucket(for: $0) == .d4 }
        let gambitItems = remaining.filter { primaryBucket(for: $0) == .gambit }
        let customItems = remaining.filter { primaryBucket(for: $0) == .custom }

        if !e4Items.isEmpty {
            groups.append(CourseGroup(
                id: "e4",
                title: sideFilter == .white ? "1. e4 Classical & Main Lines" : "Defenses vs 1. e4",
                icon: "crown.fill",
                tint: BrillyPalette.brillyTeal,
                items: e4Items
            ))
        }
        if !d4Items.isEmpty {
            groups.append(CourseGroup(
                id: "d4",
                title: sideFilter == .white ? "1. d4 Systems & 1. c4 Flank" : "Defenses vs 1. d4",
                icon: "shield.lefthalf.filled",
                tint: BrillyPalette.goldAmber,
                items: d4Items
            ))
        }
        if !gambitItems.isEmpty {
            groups.append(CourseGroup(
                id: "gambit",
                title: "Gambits & Tactical Traps",
                icon: "flame.fill",
                tint: BrillyPalette.warpPurpleText,
                items: gambitItems
            ))
        }
        if !customItems.isEmpty {
            groups.append(CourseGroup(
                id: "custom",
                title: "Custom Imported PGN",
                icon: "doc.text.fill",
                tint: BrillyPalette.inkPrimary,
                items: customItems
            ))
        }
        return groups
    }

    public var body: some View {
        ZStack {
            CosmicVoidBackdrop(style: store.surfaceStyle)

            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Picker("Side", selection: $sideFilter) {
                            Text("White (\(whiteCount))").tag(RepertoireSide.white)
                            Text("Black (\(blackCount))").tag(RepertoireSide.black)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: sideFilter) { _, _ in
                            if categoryFilter == .custom && !hasCustomForSide {
                                categoryFilter = .all
                            }
                        }

                        Button {
                            if !store.hasProAccess {
                                store.openProPaywall(feature: "Custom PGN Opening Imports")
                                return
                            }
                            showingImportSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: store.hasProAccess ? "square.and.arrow.down" : "lock.fill")
                                    .font(.caption2.weight(.bold))
                                Text("Import PGN")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(store.hasProAccess ? BrillyPalette.brillyTeal : BrillyPalette.warpPurpleText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .brillyGlassPill(store.surfaceStyle, tint: store.hasProAccess ? BrillyPalette.brillyTeal : BrillyPalette.warpPurple)
                        }
                        .buttonStyle(.plain)
                    }

                    // Search Bar + Sort Menu
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkSecondary)
                            TextField("Search Ruy Lopez, Scotch, QGD, Caro…", text: $searchQuery)
                                .textFieldStyle(.plain)
                                .font(.subheadline)
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(BrillyPalette.inkSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .brillySurface(store.surfaceStyle, cornerRadius: 14)

                        Menu {
                            ForEach(OpeningSortOption.allCases) { opt in
                                Button {
                                    sortOption = opt
                                    store.triggerHaptic(.move)
                                } label: {
                                    Label(opt.rawValue, systemImage: sortOption == opt ? "checkmark" : "arrow.up.arrow.down")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.caption2.weight(.bold))
                                Text(sortOption.rawValue)
                                    .font(.caption2.weight(.bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(sortOption == .grouped ? BrillyPalette.inkPrimary : BrillyPalette.brillyTeal)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .brillySurface(store.surfaceStyle, cornerRadius: 14, tint: sortOption == .grouped ? nil : BrillyPalette.brillyTeal)
                        }
                        .accessibilityLabel("Sort openings, currently \(sortOption.rawValue)")
                    }

                    // Category Filter Pills (hidden while typing a global search)
                    if !isSearching {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(visibleFilterChips) { chip in
                                    let active = categoryFilter == chip
                                    Button {
                                        withAnimation(.snappy(duration: 0.2)) {
                                            categoryFilter = chip
                                        }
                                        store.triggerHaptic(.move)
                                    } label: {
                                        Text(chip.label(for: sideFilter))
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(active ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(active ? BrillyPalette.brillyTeal : Color.white.opacity(0.07))
                                                    .overlay(
                                                        Capsule().strokeBorder(active ? BrillyPalette.brillyTeal : Color.white.opacity(0.09), lineWidth: 0.8)
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Text("Tap any opening for lines, FSRS drill & how to counter it.")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)

                    if courses.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: isSearching ? "magnifyingglass" : "tray")
                                .font(.title2)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                            Text(isSearching
                                 ? "No matching openings for \"\(searchQuery)\""
                                 : (categoryFilter == .daily
                                    ? "No \(sideFilter == .white ? "White" : "Black") openings pinned in Daily FSRS yet."
                                    : "No openings in this category."))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .multilineTextAlignment(.center)
                            Button {
                                searchQuery = ""
                                categoryFilter = .all
                            } label: {
                                Text(isSearching ? "Clear Search" : "Show All")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.voidBg)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(BrillyPalette.brillyTeal))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .brillySurface(store.surfaceStyle, cornerRadius: 18)
                    } else if !groupedCourses.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(groupedCourses) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 6) {
                                        Image(systemName: group.icon)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(group.tint)
                                        Text(group.title.uppercased())
                                            .font(.caption2.weight(.black))
                                            .tracking(0.8)
                                            .foregroundStyle(group.tint)
                                        Spacer()
                                        Text("\(group.items.count)")
                                            .font(.caption2.monospacedDigit().weight(.bold))
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                    }
                                    .padding(.horizontal, 4)

                                    ForEach(group.items) { course in
                                        courseCard(course)
                                    }
                                }
                            }
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(courses) { course in
                                courseCard(course)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
            .brillySoftScrollEdge()
        }
        .navigationTitle("Openings")
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(course: course)
                .environment(store)
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportCourseSheet(defaultSide: sideFilter) { importedSide in
                sideFilter = importedSide
                categoryFilter = .all
                searchQuery = ""
            }
            .environment(store)
        }
    }

    private func courseCard(_ course: OpeningCourse) -> some View {
        let unlocked = store.isCourseUnlocked(course.id)
        let courseCards = store.fsrsCards.filter { $0.courseId == course.id }
        let dueCount = courseCards.filter { FSRS6Scheduler.isCardDue($0) }.count
        let reviewed = courseCards.filter { $0.attempts > 0 }
        let avgRecall = reviewed.isEmpty
            ? 0
            : reviewed.map { FSRS6Scheduler.recallProbability(for: $0) }.reduce(0, +) / reviewed.count
        let inDaily = store.isCourseInDaily(course.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(store.copy(cosmic: course.codename.uppercased(), classic: course.difficulty.uppercased()))
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(unlocked ? BrillyPalette.brillyTeal : BrillyPalette.warpPurpleText)
                        if isSearching {
                            Text(course.side == .white ? "WHITE" : "BLACK")
                                .font(.system(size: 8.5, weight: .black))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                    }
                    Text(course.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                }
                Spacer(minLength: 6)

                if unlocked {
                    // Direct one-tap Daily FSRS inclusion toggle pill
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            store.toggleCourseInDaily(course.id)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: inDaily ? "checkmark.circle.fill" : "plus.circle")
                                .font(.caption2.weight(.bold))
                            Text(inDaily ? "Daily" : "Add Daily")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(inDaily ? BrillyPalette.voidBg : BrillyPalette.inkSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(inDaily ? BrillyPalette.brillyTeal : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(inDaily ? "Included in Daily FSRS. Tap to remove." : "Not in Daily FSRS. Tap to include.")

                    if inDaily && dueCount > 0 {
                        Text("\(dueCount) due")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(BrillyPalette.brillyTeal.opacity(0.16)))
                    }
                } else {
                    Label("PRO", systemImage: "lock.fill")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(BrillyPalette.warpPurpleText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(BrillyPalette.warpPurple.opacity(0.18))
                                .overlay(Capsule().strokeBorder(BrillyPalette.warpPurple.opacity(0.45), lineWidth: 1))
                        )
                }
            }

            Text(course.tagline)
                .font(.caption)
                .foregroundStyle(BrillyPalette.inkSecondary)
                .lineLimit(2)

            if let counters = course.counterGuide, !counters.isEmpty {
                HStack(spacing: 6) {
                    Label("\(course.lines.count) Lines", systemImage: "book.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(BrillyPalette.inkSecondary.opacity(0.6))
                    Label("\(counters.count) Counters / Defenses", systemImage: "shield.lefthalf.filled")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BrillyPalette.goldAmber)
                }
            }

            if !unlocked {
                HStack(spacing: 8) {
                    Text("\(course.lines.count) FSRS lines · Upgrade to unlock")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                    Spacer()
                    Text("Unlock Pro")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BrillyPalette.warpPurpleText)
                }
            } else if reviewed.isEmpty {
                // Inviting empty state when unstarted (0% recall) vs active recall bar
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(BrillyPalette.brillyTeal.opacity(0.14))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [BrillyPalette.brillyTeal.opacity(0.55), BrillyPalette.warpPurple.opacity(0.45)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(18, geo.size.width * 0.14))
                        }
                    }
                    .frame(height: 6)

                    HStack(spacing: 4) {
                        Text("Start Drill")
                            .font(.caption2.weight(.bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(BrillyPalette.brillyTeal)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(BrillyPalette.brillyTeal.opacity(0.14))
                            .overlay(Capsule().strokeBorder(BrillyPalette.brillyTeal.opacity(0.35), lineWidth: 1))
                    )
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView(value: Double(avgRecall), total: 100.0)
                        .tint(BrillyPalette.brillyTeal)
                    Text("\(avgRecall)% recall")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                }
            }
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: inDaily ? BrillyPalette.brillyTeal : (unlocked ? nil : BrillyPalette.warpPurple), interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            if !unlocked {
                store.openProPaywall(feature: "\(course.name) & All \(store.starterCourses.count) Starter Openings")
                return
            }
            selectedCourse = course
        }
        .contextMenu {
            if unlocked {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        store.toggleCourseInDaily(course.id)
                    }
                } label: {
                    Label(
                        inDaily ? "Remove from Daily FSRS" : "Include in Daily FSRS",
                        systemImage: inDaily ? "minus.circle" : "checkmark.circle.fill"
                    )
                }
                Button {
                    selectedCourse = course
                } label: {
                    Label("Open Course & Drills", systemImage: "book.fill")
                }
            } else {
                Button {
                    store.openProPaywall(feature: "\(course.name) & All \(store.starterCourses.count) Starter Openings")
                } label: {
                    Label("Unlock with Brilly/Der Pro", systemImage: "crown.fill")
                }
            }
        }
    }
}

// MARK: - Import Custom PGN Course Sheet

private struct ImportCourseSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let defaultSide: RepertoireSide
    let onImported: ((RepertoireSide) -> Void)?
    @State private var name: String = ""
    @State private var side: RepertoireSide = .white
    @State private var pgn: String = ""
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)
                VStack(spacing: 14) {
                    TextField("Course name (e.g. Vienna Gambit)", text: $name)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                        .foregroundStyle(BrillyPalette.inkPrimary)

                    Picker("Side", selection: $side) {
                        Text("White Repertoire").tag(RepertoireSide.white)
                        Text("Black Repertoire").tag(RepertoireSide.black)
                    }
                    .pickerStyle(.segmented)

                    TextEditor(text: $pgn)
                        .scrollContentBackground(.hidden)
                        .font(.system(.caption, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .padding(12)
                        .brillySurface(store.surfaceStyle, cornerRadius: 16)

                    if let err = errorText {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.blunderRose)
                    }

                    Button {
                        do {
                            try store.importCustomCourse(name: name, side: side, pgn: pgn)
                            onImported?(side)
                            dismiss()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    } label: {
                        Text("Import & Unlock FSRS Cards")
                            .font(.headline)
                            .foregroundStyle(BrillyPalette.voidBg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14).fill(BrillyPalette.brillyTeal))
                    }
                    .buttonStyle(.plain)
                    .disabled(pgn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
            }
            .navigationTitle("Import PGN Course")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { side = defaultSide }
        }
    }
}

// MARK: - Course Detail Sheet (Mothership + Walkthrough/Tree + FSRS Drill + PGN Export)

private struct CourseDetailSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let course: OpeningCourse

    enum CourseTab: String, CaseIterable {
        case setup = "Setup"
        case walkthrough = "Walk"
        case drill = "Drill"
        case counters = "Counters"
    }

    enum WalkLayout: String, CaseIterable {
        case line = "Line"
        case tree = "Move Tree"
    }

    @State private var activeTab: CourseTab = .setup
    @State private var walkLayout: WalkLayout = .line
    @State private var selectedLineIndex: Int = 0
    @State private var selectedCounterIndex: Int = 0
    @State private var counterStep: Int = 0
    @State private var hasInitializedCounterStep: Bool = false
    @State private var selectedTreeFen: String? = nil
    @State private var cachedTreeRoots: [RepertoireTreeNode] = []
    @State private var confirmingDelete: Bool = false

    // Walkthrough state
    @State private var walkStep: Int = 0
    @State private var isAutoPlaying: Bool = false

    // Drill state
    @State private var drillCardIds: [String] = []
    @State private var drillIdx: Int = 0
    @State private var drillBoard: ChessBoard = ChessBoard()
    @State private var drillLastMove: (from: Square, to: Square)? = nil
    @State private var drillShownAt: Date = Date()
    @State private var drillHintLevel: Int = 0
    @State private var drillHadMistake: Bool = false
    @State private var drillFeedback: String = "Play your repertoire move on the board."
    @State private var drillSolved: Bool = false
    @State private var drillSolvedBadge: MoveBadgeOverlay? = nil

    private var currentLine: OpeningLine? {
        guard !course.lines.isEmpty else { return nil }
        return course.lines[min(selectedLineIndex, course.lines.count - 1)]
    }

    private var isDeletableCustom: Bool {
        course.source == "pgn" || course.source == "lichess-study"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(spacing: 14) {
                        Picker("Mode", selection: $activeTab) {
                            ForEach(CourseTab.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch activeTab {
                        case .setup:
                            mothershipView
                        case .walkthrough:
                            walkthroughView
                        case .drill:
                            drillView
                        case .counters:
                            countersView
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle(course.name)
            .toolbar {
                if isDeletableCustom {
                    ToolbarItem(placement: .automatic) {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(BrillyPalette.blunderRose)
                        }
                        .accessibilityLabel("Delete Custom Course")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    ShareLink(item: RepertoireTreeService.exportCourseToPGN(course)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export Course PGN")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isAutoPlaying = false
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete \"\(course.name)\"?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Course & Cards", role: .destructive) {
                    store.deleteCustomCourse(id: course.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the custom repertoire and its FSRS cards from this device.")
            }
            .onAppear {
                refreshTreeCache()
            }
            .onChange(of: activeTab) { _, newTab in
                isAutoPlaying = false
                if newTab == .drill {
                    prepareDrill()
                } else if newTab == .walkthrough && walkLayout == .tree {
                    refreshTreeCache()
                }
            }
            .onChange(of: walkLayout) { _, newLayout in
                isAutoPlaying = false
                if newLayout == .tree { refreshTreeCache() }
            }
            .onChange(of: confirmingDelete) { _, confirming in
                if confirming { isAutoPlaying = false }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { isAutoPlaying = false }
            }
            .onDisappear {
                isAutoPlaying = false
            }
            .task(id: isAutoPlaying) {
                guard isAutoPlaying, let line = currentLine else { return }
                while !Task.isCancelled && isAutoPlaying {
                    try? await Task.sleep(for: .milliseconds(1200))
                    guard !Task.isCancelled, isAutoPlaying else { break }
                    if walkStep < line.moves.count {
                        walkStep += 1
                    } else {
                        isAutoPlaying = false
                    }
                }
            }
        }
    }

    private func refreshTreeCache() {
        cachedTreeRoots = RepertoireTreeService.buildTree(for: course, fsrsCards: store.fsrsCards)
    }

    // MARK: - 1. Mothership Setup

    private var mothershipView: some View {
        let board = boardAfter(moves: course.mothershipSetup.previewMoves)
        return VStack(alignment: .leading, spacing: 14) {
            InteractiveChessBoardView(
                board: board,
                orientation: course.side.pieceColor,
                theme: store.effectiveBoardTheme,
                surfaceStyle: store.surfaceStyle,
                interactive: false,
                arrows: course.mothershipSetup.arrows,
                highlights: course.mothershipSetup.highlights
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(store.copy(cosmic: "Mothership Core Plans", classic: "Core Strategic Plans"))
                    .font(.headline)
                    .foregroundStyle(BrillyPalette.brillyTeal)
                ForEach(course.mothershipSetup.corePlans, id: \.self) { plan in
                    Label(plan, systemImage: "sparkle")
                        .font(.subheadline)
                        .foregroundStyle(BrillyPalette.inkPrimary)
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 8) {
                Text("Golden Rules")
                    .font(.headline)
                    .foregroundStyle(BrillyPalette.goldAmber)
                ForEach(course.mothershipSetup.goldenRules, id: \.self) { rule in
                    Label(rule, systemImage: "shield.checkered")
                        .font(.subheadline)
                        .foregroundStyle(BrillyPalette.inkPrimary)
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)
        }
    }

    // MARK: - 1.5. Counter & Defend Against This Opening

    private var countersView: some View {
        let counters = course.counterGuide ?? []
        let counterSide = course.side.pieceColor.opposite
        let counterSideName = counterSide == .white ? "White" : "Black"

        return VStack(alignment: .leading, spacing: 14) {
            if counters.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.title2)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                    Text("No counter lines attached to this custom course yet.")
                        .font(.subheadline)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .brillySurface(store.surfaceStyle, cornerRadius: 18)
            } else {
                let safeIdx = min(selectedCounterIndex, counters.count - 1)
                let active = counters[safeIdx]
                let clampedStep = min(counterStep, active.moves.count)
                let replay = replayPrefix(moves: active.moves, count: clampedStep)

                VStack(alignment: .leading, spacing: 4) {
                    Text("HOW TO PLAY AGAINST \(course.name.uppercased())")
                        .font(.caption2.weight(.bold))
                        .tracking(0.9)
                        .foregroundStyle(BrillyPalette.goldAmber)
                    Text("Top defenses, counter-attacks & refutations playing as \(counterSideName).")
                        .font(.caption)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }

                // Counter line selector pills
                HStack(spacing: 8) {
                    ForEach(Array(counters.enumerated()), id: \.element.id) { idx, c in
                        let isSel = idx == safeIdx
                        Button {
                            selectedCounterIndex = idx
                            counterStep = min(6, c.moves.count)
                            store.triggerHaptic(.move)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.badge.uppercased())
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(isSel ? BrillyPalette.voidBg.opacity(0.85) : BrillyPalette.goldAmber)
                                Text(c.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(isSel ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSel ? BrillyPalette.goldAmber : Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(isSel ? BrillyPalette.goldAmber : Color.white.opacity(0.09), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                InteractiveChessBoardView(
                    board: replay.board,
                    orientation: counterSide,
                    theme: store.effectiveBoardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: false,
                    lastMove: replay.lastMove
                )

                // Step controls
                HStack(spacing: 10) {
                    Button {
                        counterStep = 0
                        store.triggerHaptic(.move)
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .frame(width: 40, height: 38)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(clampedStep == 0)
                    .opacity(clampedStep == 0 ? 0.4 : 1)

                    Button {
                        counterStep = max(0, clampedStep - 1)
                        store.triggerHaptic(.move)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                    }
                    .buttonStyle(.plain)
                    .disabled(clampedStep == 0)
                    .opacity(clampedStep == 0 ? 0.4 : 1)

                    Text("\(clampedStep)/\(active.moves.count)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .frame(minWidth: 44)

                    Button {
                        counterStep = min(active.moves.count, clampedStep + 1)
                        store.triggerHaptic(.move)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                    }
                    .buttonStyle(.plain)
                    .disabled(clampedStep >= active.moves.count)
                    .opacity(clampedStep >= active.moves.count ? 0.4 : 1)
                }

                // Key Idea Coaching Card + Tappable Move Chips
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkered")
                            .foregroundStyle(BrillyPalette.goldAmber)
                        Text(active.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                    }
                    Text(active.keyIdea)
                        .font(.caption)
                        .foregroundStyle(BrillyPalette.inkSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(active.moves.enumerated()), id: \.offset) { idx, san in
                                let moveLabel = idx % 2 == 0 ? "\(idx / 2 + 1).\(san)" : san
                                let isActive = (idx + 1) == clampedStep
                                Button {
                                    counterStep = idx + 1
                                    store.triggerHaptic(.move)
                                } label: {
                                    Text(moveLabel)
                                        .font(.caption2.monospaced().weight(isActive ? .black : .semibold))
                                        .foregroundStyle(isActive ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(isActive ? BrillyPalette.goldAmber : Color.white.opacity(0.08))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(14)
                .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.goldAmber)
            }
        }
        .onAppear {
            if !hasInitializedCounterStep, let first = counters.first {
                counterStep = min(6, first.moves.count)
                hasInitializedCounterStep = true
            }
        }
    }

    private func replayPrefix(moves: [String], count: Int) -> (board: ChessBoard, lastMove: (from: Square, to: Square)?) {
        var b = ChessBoard()
        var last: (from: Square, to: Square)? = nil
        for san in moves.prefix(count) {
            if let applied = try? b.apply(san: san) {
                last = (applied.move.from, applied.move.to)
            } else {
                break
            }
        }
        return (b, last)
    }

    // MARK: - 2. Guided Walkthrough + Visual Repertoire Move Tree

    private var walkthroughView: some View {
        VStack(spacing: 12) {
            Picker("Layout", selection: $walkLayout) {
                ForEach(WalkLayout.allCases, id: \.self) { l in
                    Text(l.rawValue).tag(l)
                }
            }
            .pickerStyle(.segmented)

            if walkLayout == .tree {
                treeView
            } else {
                lineWalkthroughBody
            }
        }
    }

    private var treeView: some View {
        let previewBoard = (selectedTreeFen.flatMap { try? ChessBoard(fen: $0) }) ?? boardAfter(moves: course.mothershipSetup.previewMoves)

        return VStack(spacing: 12) {
            InteractiveChessBoardView(
                board: previewBoard,
                orientation: course.side.pieceColor,
                theme: store.effectiveBoardTheme,
                surfaceStyle: store.surfaceStyle,
                interactive: false
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(store.copy(cosmic: "Repertoire Star Chart (Tap any move)", classic: "Repertoire Move Tree (Tap any move)"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.brillyTeal)

                if cachedTreeRoots.isEmpty {
                    Text("No repertoire branches found in this course.")
                        .font(.caption)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                } else {
                    ForEach(cachedTreeRoots) { node in
                        TreeNodeRow(node: node, depth: 0, selectedFen: $selectedTreeFen)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)
        }
    }

    @ViewBuilder
    private var lineWalkthroughBody: some View {
        if let line = currentLine {
            let clampedStep = max(0, min(walkStep, line.moves.count))
            let prefix = Array(line.moves.prefix(clampedStep))
            let board = boardAfter(moves: prefix)
            let activeAnnotation = line.annotations.first { $0.ply == clampedStep - 1 }

            VStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(course.lines.enumerated()), id: \.element.id) { idx, ln in
                            let sel = idx == selectedLineIndex
                            Button {
                                selectedLineIndex = idx
                                walkStep = 0
                                isAutoPlaying = false
                            } label: {
                                Text("\(ln.eco) · \(ln.title)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(sel ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(sel ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                InteractiveChessBoardView(
                    board: board,
                    orientation: course.side.pieceColor,
                    theme: store.effectiveBoardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: false,
                    arrows: activeAnnotation?.arrows ?? [],
                    highlights: activeAnnotation?.highlights ?? []
                )

                BrillyGlassCluster(style: store.surfaceStyle, spacing: 10) {
                    HStack(spacing: 10) {
                        walkBtn("backward.end.fill", label: "Start of line") { isAutoPlaying = false; walkStep = 0 }
                        walkBtn("chevron.left", label: "Previous move") { isAutoPlaying = false; walkStep = max(0, clampedStep - 1) }
                        walkBtn(isAutoPlaying ? "pause.fill" : "play.fill", label: isAutoPlaying ? "Pause" : "Auto play") {
                            if clampedStep >= line.moves.count { walkStep = 0 }
                            isAutoPlaying.toggle()
                        }
                        walkBtn("chevron.right", label: "Next move") { isAutoPlaying = false; walkStep = min(line.moves.count, clampedStep + 1) }
                        walkBtn("forward.end.fill", label: "End of line") { isAutoPlaying = false; walkStep = line.moves.count }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(clampedStep == 0 ? line.title : "Move \((clampedStep + 1) / 2): \(line.moves[clampedStep - 1])")
                            .font(.headline)
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Spacer()
                        Text("\(clampedStep) / \(line.moves.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }
                    Text(activeAnnotation?.plan ?? line.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                    if store.vibeMode == .cosmic, let cue = activeAnnotation?.cosmicCue {
                        Text(cue)
                            .font(.caption.italic())
                            .foregroundStyle(BrillyPalette.brillyTeal)
                    }

                    if let traps = activeAnnotation?.wrongMoveTraps, !traps.isEmpty {
                        Divider().overlay(Color.white.opacity(0.1))
                        ForEach(traps, id: \.playedSan) { trap in
                            VStack(alignment: .leading, spacing: 3) {
                                Label("Avoid Trap: \(trap.playedSan)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.blunderRose)
                                Text("Punishment: \(trap.punishmentLine.joined(separator: " ")) — \(trap.reason)")
                                    .font(.caption2)
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .brillySurface(store.surfaceStyle, cornerRadius: 18)

                Button {
                    store.unlockLine(courseId: course.id, lineId: line.id)
                    activeTab = .drill
                } label: {
                    Label("Unlock & Drill This Line", systemImage: "bolt.fill")
                        .font(.headline)
                        .foregroundStyle(BrillyPalette.voidBg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(BrillyPalette.brillyTeal))
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("This course has no playable lines yet.")
                .font(.subheadline)
                .foregroundStyle(BrillyPalette.inkSecondary)
                .padding(24)
        }
    }

    // MARK: - 3. FSRS Signal Strength Drill (Live card lookup + no double FSRS grading!)

    private var drillView: some View {
        VStack(spacing: 12) {
            if course.lines.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(course.lines.enumerated()), id: \.element.id) { idx, ln in
                            let sel = idx == selectedLineIndex
                            Button {
                                selectedLineIndex = idx
                                prepareDrill()
                                store.triggerHaptic(.move)
                            } label: {
                                Text("\(ln.eco) · \(ln.title)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(sel ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(sel ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if drillCardIds.isEmpty {
                Text("No drill cards available for this line.")
                    .foregroundStyle(BrillyPalette.inkSecondary)
            } else {
                let safeIdx = min(drillIdx, drillCardIds.count - 1)
                let cardId = drillCardIds[safeIdx]
                if let card = store.fsrsCards.first(where: { $0.cardId == cardId }) {
                    let fenBoard = try? ChessBoard(fen: card.fen)
                    let orient = fenBoard?.turn ?? course.side.pieceColor
                    let moveNum = fenBoard?.fullmoveNumber ?? (card.ply / 2 + 1)
                    let ann = currentLine?.annotations.first { $0.ply == card.ply }
                    let hintHighlights: [SquareHighlight] = {
                        guard drillHintLevel >= 1 && !drillSolved,
                              let legal = DailyCoachPlanner.legalMove(uci: card.expectedUci, on: drillBoard) else { return [] }
                        return [SquareHighlight(square: legal.from.algebraic, color: .plan)]
                    }()
                    let hintArrows: [BoardArrow] = {
                        guard drillHintLevel >= 2 && !drillSolved,
                              let legal = DailyCoachPlanner.legalMove(uci: card.expectedUci, on: drillBoard) else { return [] }
                        return [BoardArrow(from: legal.from.algebraic, to: legal.to.algebraic, color: .best)]
                    }()

                    HStack {
                        Text("Card \(safeIdx + 1) / \(drillCardIds.count) · Move \(moveNum)\(orient == .black ? "..." : "")")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Spacer()
                        Text("Recall \(FSRS6Scheduler.recallProbability(for: card))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }

                    InteractiveChessBoardView(
                        board: drillBoard,
                        orientation: orient,
                        theme: store.effectiveBoardTheme,
                        surfaceStyle: store.surfaceStyle,
                        interactive: !drillSolved,
                        lastMove: drillLastMove,
                        arrows: hintArrows,
                        highlights: hintHighlights,
                        moveBadge: drillSolvedBadge
                    ) { move in
                        guard !drillSolved else { return }
                        let elapsedMs = Int(Date().timeIntervalSince(drillShownAt) * 1000.0)
                        let usedHint = drillHintLevel > 0
                        let hit = move.uci == card.expectedUci
                        if hit {
                            if (try? drillBoard.apply(move)) != nil {
                                drillLastMove = (move.from, move.to)
                            }
                            drillSolved = true
                            drillHintLevel = 0
                            drillSolvedBadge = MoveBadgeOverlay(square: move.to, classification: .best)
                            if !drillHadMistake {
                                let result = store.recordOpeningAttempt(
                                    cardId: card.cardId,
                                    attempt: OpeningAttemptInput(correct: true, responseMs: elapsedMs, hintUsed: usedHint)
                                )
                                drillFeedback = "Locked in \(card.expectedSan)! FSRS graded \(result?.rating.label ?? "Good")."
                            } else {
                                store.triggerHaptic(.success)
                                drillFeedback = "Got it (\(card.expectedSan))! Scheduled soon after your earlier miss."
                            }
                        } else {
                            var temp = drillBoard
                            let playedSan = (try? temp.apply(move).san) ?? move.uci
                            let trap = ann?.wrongMoveTraps?.first { $0.playedSan == playedSan }
                            if !drillHadMistake {
                                drillHadMistake = true
                                _ = store.recordOpeningAttempt(
                                    cardId: card.cardId,
                                    attempt: OpeningAttemptInput(correct: false, responseMs: elapsedMs, hintUsed: usedHint)
                                )
                            } else {
                                store.triggerHaptic(.error)
                            }
                            if let trap {
                                drillFeedback = "Trap (\(playedSan)): \(trap.reason)"
                            } else {
                                drillFeedback = "Played \(playedSan) — try a different repertoire move, or tap Hint."
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(drillFeedback)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(drillSolved ? BrillyPalette.brillyTeal : (drillHadMistake ? BrillyPalette.blunderRose : BrillyPalette.inkPrimary))
                        if drillSolved, let plan = ann?.plan, !plan.isEmpty {
                            Text(plan)
                                .font(.caption)
                                .foregroundStyle(Color(hex: 0xCBD5E1))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .brillySurface(store.surfaceStyle, cornerRadius: 16, tint: drillSolved ? BrillyPalette.brillyTeal : nil)

                    HStack(spacing: 10) {
                        Button {
                            guard !drillSolved,
                                  let legal = DailyCoachPlanner.legalMove(uci: card.expectedUci, on: drillBoard) else { return }
                            if drillHintLevel == 0 {
                                drillHintLevel = 1
                                let pName = drillBoard[legal.from]?.type.displayName ?? "piece"
                                drillFeedback = "Hint: Look at your \(pName) on \(legal.from.algebraic)!"
                            } else if drillHintLevel == 1 {
                                drillHintLevel = 2
                                drillFeedback = "Arrow revealed: play \(card.expectedSan) (\(legal.from.algebraic) → \(legal.to.algebraic))."
                            }
                            store.triggerHaptic(.move)
                        } label: {
                            Label(
                                drillHintLevel == 0 ? "Hint" : (drillHintLevel == 1 ? "Show Arrow" : "Arrow Shown"),
                                systemImage: drillHintLevel == 0 ? "lightbulb.fill" : "arrow.up.right"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrillyPalette.goldAmber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                        }
                        .buttonStyle(.plain)
                        .disabled(drillSolved || drillHintLevel >= 2)
                        .opacity((drillSolved || drillHintLevel >= 2) ? 0.50 : 1.0)

                        Button {
                            drillIdx = (safeIdx + 1) % drillCardIds.count
                            loadDrillCard()
                        } label: {
                            Text(drillSolved ? "Next Card" : "Skip")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(drillSolved ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(drillSolved ? BrillyPalette.brillyTeal : Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func prepareDrill() {
        guard let line = currentLine else {
            drillCardIds = []
            return
        }
        store.unlockLine(courseId: course.id, lineId: line.id)
        drillCardIds = store.fsrsCards
            .filter { $0.courseId == course.id && $0.lineId == line.id }
            .sorted { $0.ply < $1.ply }
            .map(\.cardId)
        drillIdx = 0
        loadDrillCard()
    }

    private func loadDrillCard() {
        guard drillIdx < drillCardIds.count,
              let card = store.fsrsCards.first(where: { $0.cardId == drillCardIds[drillIdx] }) else { return }
        let board = (try? ChessBoard(fen: card.fen)) ?? ChessBoard()
        let moveNum = board.fullmoveNumber
        let seq: [String] = {
            if !card.moveSequence.isEmpty { return card.moveSequence }
            if let moves = currentLine?.moves, card.ply > 0, card.ply <= moves.count {
                return Array(moves.prefix(card.ply))
            }
            return []
        }()
        let oppPrev = DailyCoachPlanner.precedingMove(for: seq)
        drillBoard = board
        drillLastMove = oppPrev.map { ($0.from, $0.to) }
        drillShownAt = Date()
        drillHintLevel = 0
        drillHadMistake = false
        drillSolved = false
        drillSolvedBadge = nil
        if let oppPrev {
            drillFeedback = "After \(oppPrev.san) (Move \(moveNum)) — play your \(board.turn.displayName) repertoire reply!"
        } else {
            drillFeedback = "Move \(moveNum) — play your \(board.turn.displayName) repertoire move!"
        }
    }

    private func boardAfter(moves: [String]) -> ChessBoard {
        var b = ChessBoard()
        for m in moves {
            guard (try? b.apply(san: m)) != nil else { break }
        }
        return b
    }

    private func arrowFor(uci: String) -> [BoardArrow] {
        guard let m = ChessMove(uci: uci) else { return [] }
        return [BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)]
    }

    private func walkBtn(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
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
        .accessibilityLabel(label)
    }
}

private struct TreeNodeRow: View {
    let node: RepertoireTreeNode
    let depth: Int
    @Binding var selectedFen: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                selectedFen = node.fen
            } label: {
                HStack(spacing: 6) {
                    Text("\(node.ply / 2 + 1)\(node.ply % 2 == 0 ? "." : "...") \(node.san)")
                        .font(.caption.monospaced().weight(node.isUserMove ? .bold : .regular))
                        .foregroundStyle(selectedFen == node.fen ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary)
                    if let r = node.recallPct {
                        Circle()
                            .fill(r >= 80 ? Color(hex: 0x22C55E) : (r > 0 ? BrillyPalette.goldAmber : Color.white.opacity(0.25)))
                            .frame(width: 7, height: 7)
                    }
                    Spacer()
                }
                .padding(.leading, CGFloat(min(depth, 5)) * 12)
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)

            ForEach(node.children) { child in
                TreeNodeRow(node: child, depth: depth + 1, selectedFen: $selectedFen)
            }
        }
    }
}
