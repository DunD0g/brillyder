import SwiftUI
import BrillyDerCore

public struct InsightsTabView: View {
    @Environment(BrillyAppStore.self) private var store

    public var body: some View {
        let snap = store.insights

        ZStack {
            CosmicVoidBackdrop(style: store.surfaceStyle)

            ScrollView {
                VStack(spacing: 16) {
                    if snap.analyzedCount == 0 {
                        VStack(spacing: 14) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 44))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                            Text("No Telemetry Yet")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            Text("Analyze your first game in the Games tab to unlock accuracy trends, phase breakdowns, and opening win rates.")
                                .font(.subheadline)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(26)
                        .brillySurface(store.surfaceStyle, cornerRadius: 24)
                    } else {
                        // Hero Accuracy Ring + W/D/L
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
                                Text("\(snap.analyzedCount) Analyzed Games")
                                    .font(.headline)
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                HStack(spacing: 12) {
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
                        .padding(18)
                        .brillySurface(store.surfaceStyle, cornerRadius: 22, tint: BrillyPalette.brillyTeal)

                        // Phase Accuracy Breakdown
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

                        // Top Openings
                        if !snap.topOpenings.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Top Openings")
                                    .font(.headline)
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                ForEach(snap.topOpenings, id: \.name) { op in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(op.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(BrillyPalette.inkPrimary)
                                            Text("\(op.games) game\(op.games == 1 ? "" : "s") · \(String(format: "%.0f", op.winRate))% win")
                                                .font(.caption)
                                                .foregroundStyle(BrillyPalette.inkSecondary)
                                        }
                                        Spacer()
                                        Text("\(String(format: "%.1f", op.avgAccuracy))%")
                                            .font(.subheadline.monospacedDigit().weight(.bold))
                                            .foregroundStyle(BrillyPalette.brillyTeal)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(16)
                            .brillySurface(store.surfaceStyle, cornerRadius: 20)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Insights")
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
