import SwiftUI
import WidgetKit
import ActivityKit
import BrillyDerActivityKit

@main
struct BrillyDerWidgetBundle: WidgetBundle {
    var body: some Widget {
        BrillyBatchLiveActivityWidget()
    }
}

struct BrillyBatchLiveActivityWidget: Widget {
    private static let teal = Color(red: 45 / 255, green: 212 / 255, blue: 191 / 255)
    private static let purple = Color(red: 168 / 255, green: 85 / 255, blue: 247 / 255)
    private static let amber = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
    private static let voidBg = Color(red: 7 / 255, green: 11 / 255, blue: 20 / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrillyBatchActivityAttributes.self) { context in
            // Lock Screen / Notification Center Live Banner
            let state = context.state
            let isStalePaused = context.isStale && state.status == "analyzing"
            let isPaused = state.status == "paused" || isStalePaused
            let isComplete = state.status == "complete"
            let accent = isPaused ? Self.amber : Self.teal
            let pct = Int((min(1.0, max(0.0, state.progress)) * 100.0).rounded())

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: isComplete ? "checkmark.seal.fill" : (isPaused ? "pause.circle.fill" : "sparkles"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accent)

                    Text(
                        isComplete
                            ? "BrillyDer Batch Complete"
                            : (isPaused ? "BrillyDer Batch Paused · Tap to Resume" : "BrillyDer Batch Scan")
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                    Spacer()

                    Text("\(state.completedGames)/\(context.attributes.totalGames)")
                        .font(.caption.monospacedDigit().weight(.black))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.18)))
                }

                HStack(spacing: 6) {
                    Text(state.matchup.isEmpty ? "\(context.attributes.presetTitle) · \(context.attributes.presetElo)" : state.matchup)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)

                    Spacer()

                    if !isComplete && !isPaused && state.totalPlies > 0 {
                        Text("Ply \(state.currentPly)/\(state.totalPlies) · \(pct)%")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Text("\(context.attributes.presetTitle) · \(pct)%")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                ProgressView(value: min(1.0, max(0.0, state.progress)))
                    .tint(accent)
            }
            .padding(14)
            .activityBackgroundTint(Self.voidBg.opacity(0.92))
            .activitySystemActionForegroundColor(Self.teal)
            .widgetURL(URL(string: "brillyder://batch"))
        } dynamicIsland: { context in
            let state = context.state
            let isStalePaused = context.isStale && state.status == "analyzing"
            let isPaused = state.status == "paused" || isStalePaused
            let isComplete = state.status == "complete"
            let accent = isPaused ? Self.amber : Self.teal
            let pct = Int((min(1.0, max(0.0, state.progress)) * 100.0).rounded())

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: isComplete ? "checkmark.seal.fill" : (isPaused ? "pause.circle.fill" : "sparkles"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                        Text("BrillyDer")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(state.completedGames)/\(context.attributes.totalGames) · \(pct)%")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(
                                isComplete
                                    ? "All \(context.attributes.totalGames) games analyzed!"
                                    : (isPaused ? "Paused by iOS — Tap to auto-resume" : state.matchup)
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            Spacer()
                            Text("\(context.attributes.presetTitle) · \(context.attributes.presetElo)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Self.purple)
                        }

                        ProgressView(value: min(1.0, max(0.0, state.progress)))
                            .tint(accent)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: isComplete ? "checkmark.circle.fill" : (isPaused ? "pause.circle.fill" : "sparkles"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            } compactTrailing: {
                if isComplete {
                    Text("Done")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Self.teal)
                } else if isPaused {
                    Text("Paused")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Self.amber)
                } else {
                    Text("\(state.completedGames)/\(context.attributes.totalGames)")
                        .font(.caption2.monospacedDigit().weight(.black))
                        .foregroundStyle(Self.teal)
                }
            } minimal: {
                Gauge(value: min(1.0, max(0.0, state.progress))) {
                    Image(systemName: "sparkles")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(accent)
            }
            .keylineTint(accent)
            .widgetURL(URL(string: "brillyder://batch"))
        }
    }
}
