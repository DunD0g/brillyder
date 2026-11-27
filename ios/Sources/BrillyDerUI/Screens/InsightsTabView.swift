import SwiftUI
import BrillyDerCore

public struct InsightsTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var selectedTrendIndex: Int? = nil
    @State private var showingPerfExplainer: Bool = false

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
                            Button {
                                store.selectedTrainMode = .daily
                                store.selectedTab = .train
                                store.triggerHaptic(.move)
                            } label: {
                                Text("Warmup")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.voidBg)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(BrillyPalette.brillyTeal))
                                    .contentShape(Capsule())
                            }
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
                            Button {
                                store.selectedTab = .games
                            } label: {
                                Text("Go to Games")
                                    .font(.headline)
                                    .foregroundStyle(BrillyPalette.voidBg)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 11)
                                    .background(Capsule().fill(BrillyPalette.brillyTeal))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(BrillyPressScaleStyle())
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
                                            Button {
                                                showingPerfExplainer = true
                                                store.triggerHaptic(.move)
                                            } label: {
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
                                                    Image(systemName: "info.circle")
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundStyle(BrillyPalette.goldAmber.opacity(0.75))
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule()
                                                        .fill(BrillyPalette.goldAmber.opacity(0.12))
                                                        .overlay(Capsule().strokeBorder(BrillyPalette.goldAmber.opacity(0.35), lineWidth: 0.9))
                                                )
                                            }
                                            .buttonStyle(BrillyPressScaleStyle())
                                            .accessibilityLabel("Estimated performance rating \(perf). Tap for explanation and improvement plan.")
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
                                        Button {
                                            store.openMotifTrainer(tag: m.tag)
                                        } label: {
                                            Text("Train")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(BrillyPalette.voidBg)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(BrillyPalette.brillyTeal))
                                                .contentShape(Capsule())
                                        }
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
                                        let handles = store.userHandles
                                        if let matchingGame = store.analyzedGames.first(where: {
                                            guard !$0.game.isCustomFenGame,
                                                  $0.game.resolvedUserColor(handles: handles) != nil else { return false }
                                            let opName = ($0.openingLineDetected ?? $0.game.openingName).lowercased()
                                            return opName.contains(needle) || needle.contains(opName)
                                        }) {
                                            store.openGameAtPly(gameId: matchingGame.id, ply: 1)
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
        .sheet(isPresented: $showingPerfExplainer) {
            if let perf = snap.avgPerformanceElo {
                PerfEloExplainerSheet(perfElo: perf, snapshot: snap, advanced: adv)
                    .environment(store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func accuracyTrendAndCheckpointsCard() -> some View {
        let handles = store.userHandles
        let validGames = store.analyzedGames.filter {
            !$0.plies.isEmpty && !$0.game.isCustomFenGame && $0.game.resolvedUserColor(handles: handles) != nil
        }
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
                        store.openGameAtPly(gameId: ag.id, ply: 1)
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

// MARK: - Performance Elo Explainer & Roadmap Sheet

private struct PerfEloExplainerSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let perfElo: Int
    let snapshot: InsightsSnapshot
    let advanced: AdvancedInsightsReport

    private var primaryRating: (speed: String, rating: Int)? {
        snapshot.currentRatings.first
    }

    private var eloGap: Int? {
        guard let actual = primaryRating?.rating else { return nil }
        return perfElo - actual
    }

    private var blundersPerGame: Double {
        Double(snapshot.totalBlunders) / Double(max(1, snapshot.analyzedCount))
    }

    private var expectedBaselineAccuracy: Double {
        let anchor = Double(primaryRating?.rating ?? 1200)
        return ChessMath.clamp(56.0 + (anchor - 1000.0) * 0.018, min: 52.0, max: 90.0)
    }

    private var weakestPhase: (name: String, pct: Double)? {
        let phases: [(String, Double)] = [
            ("Opening", snapshot.openingAccuracy),
            ("Middlegame", snapshot.middlegameAccuracy),
            ("Endgame", snapshot.endgameAccuracy),
        ].filter { $0.1 > 0.1 }
        return phases.min { $0.1 < $1.1 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        comparisonHeroCard
                        howCalculatedCard
                        whyActualDiffersCard
                        roadmapActionCard
                    }
                    .padding(16)
                }
                .brillySoftScrollEdge()
            }
            .navigationTitle("Performance Elo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    private var comparisonHeroCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let actual = primaryRating {
                    VStack(spacing: 3) {
                        Text("\(actual.speed.uppercased()) ELO")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                        Text("\(actual.rating)")
                            .font(.title.monospacedDigit().weight(.black))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text("Actual rating")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.black))
                        .foregroundStyle(BrillyPalette.goldAmber)
                }

                VStack(spacing: 3) {
                    Text("PERF ELO")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(BrillyPalette.goldAmber)
                    Text("~\(perfElo)")
                        .font(.title.monospacedDigit().weight(.black))
                        .foregroundStyle(BrillyPalette.goldAmber)
                    Text("\(String(format: "%.1f", snapshot.avgAccuracy))% avg acc")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(BrillyPalette.goldAmber.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BrillyPalette.goldAmber.opacity(0.32), lineWidth: 0.9))
                )
            }

            if let gap = eloGap {
                let badgeText: String = {
                    if gap >= 50 {
                        return "+\(gap) Elo ceiling — your move quality is already ahead of your rating!"
                    } else if gap <= -50 {
                        return "Actual rating is +\(-gap) Elo ahead of recent move accuracy — strong practical grit!"
                    } else {
                        return "Perf Elo & Actual Rating are tightly aligned."
                    }
                }()
                Text(badgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gap >= 50 ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.goldAmber)
    }

    private var howCalculatedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How We Calculated ~\(perfElo)", systemImage: "function")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BrillyPalette.brillyTeal)

            explainerBullet(
                icon: "target",
                tint: BrillyPalette.brillyTeal,
                title: "1. Game Rating Anchor",
                body: primaryRating.map {
                    "Each game starts anchored at the average of your rating and your opponent's rating (around ~\($0.rating) in your \($0.speed) games)."
                } ?? "Each game starts anchored at the average rating of both players in that match."
            )

            explainerBullet(
                icon: "gauge.with.needle.fill",
                tint: BrillyPalette.warpPurpleText,
                title: "2. Move Accuracy Lift",
                body: "At your tier, average engine accuracy is around \(String(format: "%.0f", expectedBaselineAccuracy))%. Your \(String(format: "%.1f", snapshot.avgAccuracy))% average across \(snapshot.analyzedCount) game\(snapshot.analyzedCount == 1 ? "" : "s") adds ~19 Elo for every +1% above baseline."
            )

            explainerBullet(
                icon: "trophy.fill",
                tint: BrillyPalette.goldAmber,
                title: "3. Game Result Adjustment",
                body: "Wins add +85 and losses subtract -85 to keep move quality tied to real outcomes, then we average across all analyzed games."
            )
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    private var whyActualDiffersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                (eloGap ?? 1) >= 0 ? "Why Your Actual Rating Is Lower" : "Why Actual Rating Differs",
                systemImage: "questionmark.circle.fill"
            )
            .font(.subheadline.weight(.bold))
            .foregroundStyle(BrillyPalette.warpPurpleText)

            explainerBullet(
                icon: "exclamationmark.triangle.fill",
                tint: BrillyPalette.blunderRose,
                title: "One Blunder Can Erase 30 Great Moves",
                body: "Perf Elo rewards your average move quality (\(String(format: "%.1f", snapshot.avgAccuracy))%), but actual Elo only scores the final result (\(snapshot.wins)W · \(snapshot.draws)D · \(snapshot.losses)L). At \(String(format: "%.2f", blundersPerGame)) blunders/game (\(snapshot.totalBlunders) ??), a single hanging piece or missed tactic can flip a dominant game into a loss."
            )

            explainerBullet(
                icon: "person.2.fill",
                tint: BrillyPalette.goldAmber,
                title: "Opponent Resistance Scales Up",
                body: primaryRating.map {
                    "Playing \(String(format: "%.0f", snapshot.avgAccuracy))% accuracy against ~\($0.rating) opponents is much easier than holding it against ~\(perfElo) players, who create sharper threats and punish small slips."
                } ?? "Higher-rated opponents create sharper complications and punish minor inaccuracies that lower-rated opponents often miss."
            )

            if !store.blownLeads.isEmpty || advanced.impulseBlunders > 0 {
                let blownCount = store.blownLeads.count
                let impulse = advanced.impulseBlunders
                let leakText: String = {
                    if blownCount > 0 && impulse > 0 {
                        return "You have \(blownCount) blown winning lead\(blownCount == 1 ? "" : "s") (+2.5 or better) and \(impulse) impulse blunder\(impulse == 1 ? "" : "s") (<5s moves with plenty of time left). Fixing just those two leaks turns existing skill straight into rating points."
                    } else if blownCount > 0 {
                        return "You let \(blownCount) winning position\(blownCount == 1 ? "" : "s") (+2.5 or better) slip away — converting half of those alone is worth +100 Elo."
                    } else {
                        return "You made \(impulse) impulse error\(impulse == 1 ? "" : "s") in under 5 seconds with plenty of clock left — slowing down in sharp spots pays off immediately."
                    }
                }()
                explainerBullet(
                    icon: "bolt.slash.fill",
                    tint: BrillyPalette.goldAmber,
                    title: "Unconverted Leads & Fast Slips",
                    body: leakText
                )
            }
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    private var roadmapActionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How to Reach ~\(perfElo) Actual Elo", systemImage: "arrow.up.right.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BrillyPalette.brillyTeal)

            if let topMotif = advanced.missedMotifs.first {
                actionRow(
                    title: "1. Cut Your #1 Blunder Leak (\(topMotif.tag))",
                    detail: "\(topMotif.count) errors · avg -\(Int(topMotif.avgWinLoss))% win chance. Cutting blunders from \(String(format: "%.2f", blundersPerGame))/game under 0.5/game is the fastest rating jump.",
                    cta: "Drill"
                ) {
                    dismiss()
                    store.openMotifTrainer(tag: topMotif.tag)
                }
            } else {
                actionRow(
                    title: "1. Cut Blunders Below 0.5 / Game",
                    detail: "You're averaging \(String(format: "%.2f", blundersPerGame)) blunders/game. Run a 5-second blunder check (Checks, Captures, Threats) before committing.",
                    cta: "Mistakes"
                ) {
                    dismiss()
                    store.selectedTrainMode = .mistakes
                    store.selectedTab = .train
                }
            }

            if !store.blownLeads.isEmpty {
                actionRow(
                    title: "2. Lock In Winning Positions",
                    detail: "Replay your \(store.blownLeads.count) blown +2.5 lead\(store.blownLeads.count == 1 ? "" : "s") against the engine until simplifying & converting feels automatic.",
                    cta: "Convert"
                ) {
                    dismiss()
                    store.selectedTrainMode = .conversion
                    store.selectedTab = .train
                }
            }

            if let weak = weakestPhase {
                let stepNum = store.blownLeads.isEmpty ? "2" : "3"
                let weakDetail: String = {
                    if weak.name == "Endgame" {
                        return "Your endgame trails your opening (\(String(format: "%.1f", snapshot.openingAccuracy))%). Master key pawn & rook endgames to turn draws into wins."
                    } else if weak.name == "Opening" {
                        return "Lock in your first 8 moves with Daily FSRS drills so you reach comfortable middlegames every game."
                    } else {
                        return "Drill middlegame tactics & personal mistakes so your strong openings convert cleanly."
                    }
                }()
                actionRow(
                    title: "\(stepNum). Shore Up Your \(weak.name) (\(String(format: "%.1f", weak.pct))%)",
                    detail: weakDetail,
                    cta: weak.name == "Opening" ? "Openings" : "Train"
                ) {
                    dismiss()
                    if weak.name == "Opening" {
                        store.selectedTab = .openings
                    } else if weak.name == "Endgame" && store.hasProAccess {
                        let cat: EndgameCategory = advanced.endgameWeaknesses.first?.category ?? .pawn
                        store.openEndgameLab(category: cat)
                    } else {
                        store.selectedTrainMode = .mistakes
                        store.selectedTab = .train
                    }
                }
            }

            if advanced.impulseBlunders > 0 {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "timer")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.goldAmber)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(BrillyPalette.goldAmber.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Your Clock + 2-Loss Stop-Loss")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text("Pause 5–10s before moves when you have >3m left (\(advanced.impulseBlunders) impulse slips so far), and stop queueing after 2 straight losses to protect your Elo.")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }
                }
            }
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.brillyTeal)
    }

    private func explainerBullet(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                Text(body)
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionRow(title: String, detail: String, cta: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button(action: action) {
                Text(cta)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(BrillyPalette.voidBg)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(BrillyPalette.brillyTeal))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
}
