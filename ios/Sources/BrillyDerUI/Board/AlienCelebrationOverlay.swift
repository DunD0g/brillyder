import SwiftUI

public struct CelebrationEvent: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable {
        case brilliant
        case blunder
    }

    public let id: UUID
    public let kind: Kind
    public let vibe: VibeMode
    public let headline: String
    public let message: String

    public init(kind: Kind, vibe: VibeMode) {
        self.id = UUID()
        self.kind = kind
        self.vibe = vibe
        let mood: BrillyAlienMood = (kind == .brilliant) ? .brilliant : .blunder
        let pool = BrillyShareQuips.pool(for: mood, vibe: vibe)
        if kind == .brilliant {
            self.headline = vibe == .cosmic ? "BRILLIANT SIGNAL DETECTED" : "BRILLIANT MOVE"
            self.message = pool.randomElement() ?? "Brilliant!"
        } else {
            self.headline = vibe == .cosmic ? "HULL BREACH DETECTED" : "BLUNDER DETECTED"
            self.message = pool.randomElement() ?? "Blunder!"
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
                if event.vibe == .cosmic {
                    BrillyAlienUFOView(mood: isBril ? .brilliant : .blunder, size: 62, showBeam: true)
                } else {
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .brillySurface(surfaceStyle, cornerRadius: 20, tint: accent)
            .shadow(color: accent.opacity(0.32), radius: 14, y: 4)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
