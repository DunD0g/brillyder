import SwiftUI

public struct CelebrationEvent: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable {
        case brilliant
        case blunder
    }

    public let id: UUID
    public let kind: Kind
    public let headline: String
    public let message: String

    public init(kind: Kind, vibe: VibeMode) {
        self.id = UUID()
        self.kind = kind
        let cosmicBrilliant = [
            "Beam me up, Magnus — that sacrifice isn't from this planet!",
            "Area 51 called. They want their tactics back.",
            "Humans aren't supposed to calculate that!",
            "Certified Galaxy-Brain Sacrifice!",
            "Somewhere, a grandmaster just spilled their coffee.",
            "NASA renamed a constellation after that move.",
        ]
        let cosmicBlunder = [
            "Houston, we dropped a piece.",
            "The UFO is facepalming. Slowly.",
            "Alien scan complete: yep, that one hurts.",
            "Mission Control: We recommend not doing that.",
        ]
        let classicBrilliant = [
            "Brilliant sacrifice — the sharpest move in the position.",
            "Tactical masterpiece! Material offered for decisive play.",
            "Outstanding calculation — engine's top sacrificial idea.",
        ]
        let classicBlunder = [
            "Serious blunder — check the engine's refutation.",
            "Missed tactic — retry this position to lock in the pattern.",
        ]

        if kind == .brilliant {
            self.headline = vibe == .cosmic ? "BRILLIANT SIGNAL DETECTED" : "BRILLIANT MOVE"
            self.message = (vibe == .cosmic ? cosmicBrilliant : classicBrilliant).randomElement() ?? "Brilliant!"
        } else {
            self.headline = vibe == .cosmic ? "HULL BREACH DETECTED" : "BLUNDER DETECTED"
            self.message = (vibe == .cosmic ? cosmicBlunder : classicBlunder).randomElement() ?? "Blunder!"
        }
    }
}

/// Non-blocking floating toast banner for Brilliant (!!) & Blunder (??) moments.
public struct AlienCelebrationBanner: View {
    let event: CelebrationEvent
    let surfaceStyle: SurfaceStyle
    let onDismiss: () -> Void

    public var body: some View {
        let isBril = event.kind == .brilliant
        let accent = isBril ? BrillyPalette.brillyTeal : BrillyPalette.blunderRose

        Button(action: onDismiss) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.22))
                        .frame(width: 44, height: 44)
                    if isBril {
                        BrillyGemIcon(size: 24, color: BrillyPalette.brillyTeal)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(BrillyPalette.blunderRose)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.headline)
                        .font(.caption2.weight(.black))
                        .tracking(1.1)
                        .foregroundStyle(accent)
                    Text(event.message)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .brillySurface(surfaceStyle, cornerRadius: 20, tint: accent)
            .shadow(color: accent.opacity(0.30), radius: 14, y: 4)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
