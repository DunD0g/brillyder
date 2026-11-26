import SwiftUI
import BrillyDerCore

public struct InsightsTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var selectedTrendIndex: Int? = nil

    public var body: some View {
        let snap = store.insights
        let adv = store.advancedInsights

        ZStack {
            CosmicVoidBackdrop(style: store.surfaceStyle)

            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Active Scout Gameplan Card
                    if let plan = store.scoutGameplan {
                        scoutGameplanCard(plan)
                    }

                    // MARK: - Tilt Guard Stop-Loss Banner
                    if adv.currentLossStreak >= 2 {
                        HStack(spacing: 10) {
                            Image(systemName: "flame.circle.fill")
                                .font(.title2)
                                .foregroundStyle(BrillyPalette.blunderRose)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.copy(
                                    cosmic: "Tilt Thrusters Overheating (\(adv.currentLossStreak)L Streak)",
                                    classic: "Stop-Loss Alert (\(adv.currentLossStreak) Losses in a Row)"
                                ))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BrillyPalette.blunderRose)
                                Text(store.copy(
                                    cosmic: "Take a 15-minute breather or run a quick 60s Gravity Check before queueing again.",
                                    classic: "Take a short break or run a 60-second warmup before queueing again."
                                ))
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                            }
                            Spacer(minLength: 6)
                            Button("Warmup") {
                                store.selectedTrainMode = .daily
                                store.selectedTab = .train
                                store.triggerHaptic(.move)
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.voidBg)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(BrillyPalette.brillyTeal))
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.blunderRose)
                    }

                    if snap.analyzedCount == 0 {
                        VStack(spacing: 14) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 44))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                            Text(store.copy(cosmic: "No Telemetry Yet", classic: "No Analytics Yet"))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            Text("Analyze any game (including built-in showcase games) in the Games tab to unlock Accuracy Rings, Clock Leaks, Tilt Guard, Missed Motifs, and Endgame Weaknesses.")
                                .font(.subheadline)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                                .multilineTextAlignment(.center)
                            Button("Go to Games") {
                                store.selectedTab = .games
                            }
                            .font(.headline)
                            .foregroundStyle(BrillyPalette.voidBg)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(BrillyPalette.brillyTeal))
                            .buttonStyle(.plain)
                        }
                        .padding(26)
                        .brillySurface(store.surfaceStyle, cornerRadius: 24)
                    } else {
                        // MARK: - 1. Hero Accuracy Ring + W/D/L + Current Elo
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 18) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.10), lineWidth: 10)
                                    Circle()
                                        .trim(from: 0, to: CGFloat(ChessMath.clamp(snap.avgAccuracy / 100.0, min: 0, max: 1)))
                                        .stroke(
                                            LinearGradient(
                                                colors: [BrillyPalette.brillyTeal, BrillyPalette.warpPurple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                                        )
                                        .rotationEffect(.degrees(-90))
                                    VStack(spacing: 2) {
                                        Text("\(String(format: "%.1f", snap.avgAccuracy))%")
                                            .font(.title3.monospacedDigit().weight(.bold))
                                            .foregroundStyle(BrillyPalette.inkPrimary)
                                        Text("Avg Acc")
                                            .font(.caption2)
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                    }
                                }
                                .frame(width: 96, height: 96)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(snap.analyzedCount) Analyzed Game\(snap.analyzedCount == 1 ? "" : "s")")
                                        .font(.headline)
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                    HStack(spacing: 10) {
                                        recordPill("W", snap.wins, Color(hex: 0x22C55E))
                                        recordPill("D", snap.draws, BrillyPalette.inkSecondary)
                                        recordPill("L", snap.losses, BrillyPalette.blunderRose)
                                    }
                                    HStack(spacing: 12) {
                                        Label("\(snap.totalBrilliants) !!", systemImage: "sparkles")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(BrillyPalette.brillyTeal)
                                        Label("\(snap.totalBlunders) ??", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(BrillyPalette.blunderRose)
                                    }
                                }
                                Spacer(minLength: 0)
                            }

                            if !snap.currentRatings.isEmpty || snap.avgPerformanceElo != nil {
                                Divider().overlay(Color.white.opacity(0.10))
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(snap.currentRatings, id: \.speed) { item in
                                            HStack(spacing: 5) {
                                                Text(item.speed)
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                                Text("\(item.rating)")
                                                    .font(.caption.monospacedDigit().weight(.black))
                                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(Color.white.opacity(0.07))
                                                    .overlay(Capsule().strokeBorder(BrillyPalette.brillyTeal.opacity(0.28), lineWidth: 0.8))
                                            )
                                        }
                                        if let perf = snap.avgPerformanceElo {
                                            HStack(spacing: 5) {
                                                Image(systemName: "chart.line.uptrend.xyaxis")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(BrillyPalette.goldAmber)
                                                Text("Perf")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                                Text("~\(perf)")
                                                    .font(.caption.monospacedDigit().weight(.black))
                                                    .foregroundStyle(BrillyPalette.goldAmber)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(BrillyPalette.goldAmber.opacity(0.12))
                                                    .overlay(Capsule().strokeBorder(BrillyPalette.goldAmber.opacity(0.32), lineWidth: 0.8))
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .padding(18)
                        .brillySurface(store.surfaceStyle, cornerRadius: 22, tint: BrillyPalette.brillyTeal)

                        // MARK: - 1.5. Accuracy Trend & 20-Game Checkpoints (Scoped Strictly to Recent 20!)
                        accuracyTrendAndCheckpointsCard()

                        // MARK: - 2. Clock Leaks & Tilt Guard
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.copy(cosmic: "Clock Leaks & Tilt Guard", classic: "Time Management & Tilt"))
                                .font(.headline)
                                .foregroundStyle(BrillyPalette.inkPrimary)

                            HStack(spacing: 10) {
                                miniMetric("Impulse (<5s)", value: "\(adv.impulseBlunders)", tint: BrillyPalette.goldAmber)
                                miniMetric("Time Trouble (<60s)", value: "\(adv.timeTroubleBlunders)", tint: BrillyPalette.blunderRose)
                            }

                            HStack(spacing: 8) {
                                ForEach(adv.tiltBuckets) { b in
                                    VStack(spacing: 4) {
                                        Text("\(Int(b.winRatePct))%")
                                            .font(.caption.monospacedDigit().weight(.bold))
                                            .foregroundStyle(b.games > 0 ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)
                                        Text(b.label)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(BrillyPalette.inkPrimary)
                                        Text("\(b.games)g")
                                            .font(.caption2)
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                                }
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20)

                        // MARK: - 3. Phase Accuracy Breakdown
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Accuracy by Phase")
                                .font(.headline)
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            phaseBar(label: "Opening", pct: snap.openingAccuracy, tint: BrillyPalette.brillyTeal)
                            phaseBar(label: "Middlegame", pct: snap.middlegameAccuracy, tint: BrillyPalette.warpPurple)
                            phaseBar(label: "Endgame", pct: snap.endgameAccuracy, tint: BrillyPalette.goldAmber)
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20)

                        // MARK: - 4. Patterns You Miss Most (1-Tap Train!)
                        if !adv.missedMotifs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Patterns You Miss Most")
                                    .font(.headline)
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                ForEach(adv.missedMotifs) { m in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.tag)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(BrillyPalette.inkPrimary)
                                            Text("\(m.count) error\(m.count == 1 ? "" : "s") · avg -\(Int(m.avgWinLoss))% win")
                                                .font(.caption)
                                                .foregroundStyle(BrillyPalette.inkSecondary)
                                        }
                                        Spacer()
                                        Button("Train") {
                                            store.openMotifTrainer(tag: m.tag)
                                        }
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(BrillyPalette.voidBg)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(BrillyPalette.brillyTeal))
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(16)
                            .brillySurface(store.surfaceStyle, cornerRadius: 20)
                        }

                        // MARK: - 5. Endgame Weakness Tracker
                        if !adv.endgameWeaknesses.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Endgame Weakness Tracker")
                                    .font(.headline)
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                ForEach(adv.endgameWeaknesses) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.category.rawValue)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(BrillyPalette.inkPrimary)
                                            Text("\(String(format: "%.1f", item.accuracy))% acc · \(item.errors) error\(item.errors == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundStyle(BrillyPalette.inkSecondary)
                                        }
                                        Spacer()
                                        Button {
                                            if store.hasProAccess {
                                                store.openEndgameLab(category: item.category)
                                            } else {
                                                store.openProPaywall(feature: "Syzygy Endgame Lab")
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text("Lab")
                                                if !store.hasProAccess {
                                                    Image(systemName: "lock.fill")
                                                        .font(.system(size: 9, weight: .bold))
                                                }
                                            }
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(BrillyPalette.inkPrimary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(16)
                            .brillySurface(store.surfaceStyle, cornerRadius: 20)
                        }

                        // MARK: - 6. Top Openings (Tappable — jump to matching course or game)
                        if !snap.topOpenings.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Top Openings")
                                        .font(.headline)
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                    Spacer()
                                    Text("Tap to inspect game")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(BrillyPalette.inkSecondary)
                                }
                                ForEach(snap.topOpenings, id: \.name) { op in
                                    Button {
                                        let needle = op.name.lowercased()
                                        if let matchingGame = store.analyzedGames.first(where: {
                                            let opName = ($0.openingLineDetected ?? $0.game.openingName).lowercased()
                                            return opName.contains(needle) || needle.contains(opName)
                                        }) {
                                            store.activeAnalyzedGame = matchingGame
                                            store.selectedTab = .analyze
                                        } else {
                                            store.selectedTab = .openings
                                        }
                                        store.triggerHaptic(.move)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(op.name)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                                    .lineLimit(1)
                                                Text("\(op.games) game\(op.games == 1 ? "" : "s") · \(String(format: "%.0f", op.winRate))% win")
                                                    .font(.caption)
                                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                            }
                                            Spacer()
                                            Text("\(String(format: "%.1f", op.avgAccuracy))%")
                                                .font(.subheadline.monospacedDigit().weight(.bold))
                                                .foregroundStyle(BrillyPalette.brillyTeal)
                                            Image(systemName: "chevron.right")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(BrillyPalette.inkSecondary.opacity(0.6))
                                        }
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(16)
                            .brillySurface(store.surfaceStyle, cornerRadius: 20)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .brillySoftScrollEdge()
        }
        .navigationTitle("Insights")
    }

    private func accuracyTrendAndCheckpointsCard() -> some View {
        let handles = store.userHandles
        let validGames = store.analyzedGames.filter { !$0.plies.isEmpty && !$0.game.isCustomFenGame }
        let recent = Array(validGames.sorted { $0.game.createdAt < $1.game.createdAt }.suffix(20))
        let accPoints: [Double] = recent.map { ag in
            let c = ag.game.resolvedUserColor(handles: handles) ?? .white
            return (c == .white ? ag.whiteSummary : ag.blackSummary).accuracy
        }
        let evalAt10List: [Double] = recent.compactMap { ag in
            guard ag.plies.count >= 18 else { return nil }
            let c = ag.game.resolvedUserColor(handles: handles) ?? .white
            let cp = ag.plies[min(19, ag.plies.count - 1)].evalAfter.cpWhite
            return Double(c == .white ? cp : -cp) / 100.0
        }
        let avgEval10 = evalAt10List.isEmpty ? 0.0 : evalAt10List.reduce(0, +) / Double(evalAt10List.count)

        // Compute impulse & blown lead metrics strictly over the same `recent` 20-game window (never >100%)
        let recentReport = AdvancedInsightsService.buildReport(analyzedGames: recent, handles: handles)
        let recentBlownCount = WoodpeckerAndConversion.extractBlownLeads(from: recent, handles: handles).count
        let impulsePerGame = Double(recentReport.impulseBlunders) / Double(max(1, recent.count))
        let blownPct = min(100.0, Double(recentBlownCount) / Double(max(1, recent.count)) * 100.0)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Last \(recent.count)-Game Checkpoints & Accuracy Trend")
                .font(.headline)
                .foregroundStyle(BrillyPalette.inkPrimary)

            if accPoints.count >= 2 {
                let activeIdx: Int? = selectedTrendIndex.flatMap { $0 < recent.count ? $0 : nil }
                GeometryReader { geo in
                    ZStack {
                        Canvas { ctx, size in
                            let pad: CGFloat = 8
                            let usableW = max(1, size.width - pad * 2)
                            var path = Path()
                            for (i, acc) in accPoints.enumerated() {
                                let x = pad + CGFloat(i) / CGFloat(max(1, accPoints.count - 1)) * usableW
                                let y = size.height * (1.0 - CGFloat(ChessMath.clamp(acc / 100.0, min: 0.08, max: 0.94)))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            ctx.stroke(path, with: .color(BrillyPalette.brillyTeal), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            for (i, acc) in accPoints.enumerated() {
                                let x = pad + CGFloat(i) / CGFloat(max(1, accPoints.count - 1)) * usableW
                                let y = size.height * (1.0 - CGFloat(ChessMath.clamp(acc / 100.0, min: 0.08, max: 0.94)))
                                let isSel = (activeIdx == i)
                                let r: CGFloat = isSel ? 5.0 : 3.0
                                ctx.fill(
                                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                    with: .color(isSel ? BrillyPalette.goldAmber : BrillyPalette.brillyTeal)
                                )
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let pad: CGFloat = 8
                            let usableW = max(1, geo.size.width - pad * 2)
                            let norm = ChessMath.clamp(Double((location.x - pad) / usableW), min: 0.0, max: 1.0)
                            let idx = Int((norm * Double(accPoints.count - 1)).rounded())
                            selectedTrendIndex = idx
                            store.triggerHaptic(.move)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { val in
                                    guard abs(val.translation.width) > abs(val.translation.height) else { return }
                                    let pad: CGFloat = 8
                                    let usableW = max(1, geo.size.width - pad * 2)
                                    let norm = ChessMath.clamp(Double((val.location.x - pad) / usableW), min: 0.0, max: 1.0)
                                    let idx = Int((norm * Double(accPoints.count - 1)).rounded())
                                    if selectedTrendIndex != idx {
                                        selectedTrendIndex = idx
                                        store.triggerHaptic(.move)
                                    }
                                }
                        )
                    }
                }
                .frame(height: 66)
                .padding(.vertical, 4)

                if let idx = activeIdx {
                    let ag = recent[idx]
                    let userCol = ag.game.resolvedUserColor(handles: handles) ?? .white
                    let rawOpp = userCol == .white ? ag.game.black.name : ag.game.white.name
                    let oppMasked = store.maskedPlayerName(rawOpp, side: userCol.opposite)
                    Button {
                        store.activeAnalyzedGame = ag
                        store.selectedTab = .analyze
                        store.triggerHaptic(.move)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Game #\(idx + 1) vs")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BrillyPalette.inkSecondary)
                            Text(oppMasked.text)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .lineLimit(1)
                                .blur(radius: oppMasked.isBlurred ? 4 : 0)
                            Text("· \(String(format: "%.1f", accPoints[idx]))%")
                                .font(.caption2.monospacedDigit().weight(.black))
                                .foregroundStyle(BrillyPalette.goldAmber)
                            Spacer()
                            Label("Analyze", systemImage: "arrow.right.circle.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(BrillyPalette.goldAmber.opacity(0.35), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Tap or scrub any point to inspect that game")
                        .font(.caption2)
                        .foregroundStyle(BrillyPalette.inkSecondary.opacity(0.75))
                }
            }

            HStack(spacing: 8) {
                miniMetric("Eval @ M10", value: String(format: "%+.1f", avgEval10), tint: avgEval10 >= 0 ? BrillyPalette.brillyTeal : BrillyPalette.blunderRose)
                miniMetric("Impulse / g", value: String(format: "%.1f", impulsePerGame), tint: BrillyPalette.goldAmber)
                miniMetric("Blown Lead", value: "\(Int(blownPct.rounded()))%", tint: BrillyPalette.warpPurple)
            }
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    private func scoutGameplanCard(_ plan: ScoutGameplan) -> some View {
        let maskedOpp = store.maskedPlayerName(plan.opponentName, side: .black)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "binoculars.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BrillyPalette.warpPurple)
                    Text("How to Beat")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BrillyPalette.warpPurple)
                    Text(maskedOpp.text)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BrillyPalette.warpPurple)
                        .blur(radius: maskedOpp.isBlurred ? 5 : 0)
                }
                Spacer()
                Button("Exit Scout") { store.clearScout() }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.blunderRose)
                    .buttonStyle(.plain)
            }

            Text(plan.tacticalSummary)
                .font(.caption)
                .foregroundStyle(BrillyPalette.inkPrimary)

            if !plan.favoriteWhiteOpenings.isEmpty {
                Text("As White: \(plan.favoriteWhiteOpenings.map { "\($0.name) (\($0.games)g)" }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
            if !plan.favoriteBlackOpenings.isEmpty {
                Text("As Black: \(plan.favoriteBlackOpenings.map { "\($0.name) (\($0.games)g)" }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.warpPurple)
    }

    private func miniMetric(_ label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(BrillyPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private func recordPill(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).fontWeight(.black)
            Text("\(count)").monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.15)))
    }

    private func phaseBar(label: String, pct: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                Spacer()
                Text("\(String(format: "%.1f", pct))%")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
            }
            ProgressView(value: ChessMath.clamp(pct, min: 0, max: 100), total: 100)
                .tint(tint)
        }
    }
}
