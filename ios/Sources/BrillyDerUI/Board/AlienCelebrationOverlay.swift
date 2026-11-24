import SwiftUI

public struct CelebrationEvent: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable {
        case brilliant
        case blunder
    }

    public let id: UUID
    public let kind: Kind
    public let vibe: VibeMode
    public let calloutStyle: CalloutStyle
    public let shoutPrefix: String
    public let shoutAccent: String
    public let tag: String
    public let message: String

    public init(kind: Kind, vibe: VibeMode, calloutStyle: CalloutStyle = .brillyDer) {
        self.id = UUID()
        self.kind = kind
        self.vibe = vibe
        self.calloutStyle = calloutStyle
        let mood: BrillyAlienMood = (kind == .brilliant) ? .brilliant : .blunder
        let pool = BrillyShareQuips.pool(for: mood, vibe: vibe, calloutStyle: calloutStyle)

        switch (kind, calloutStyle) {
        case (.brilliant, .brillyDer):
            let shouts: [(String, String)] = [
                ("VERY NICE, ", "BRILLY!!"),
                ("BRILLY!!", " MOVE!"),
                ("PURE ", "BRILLY!!"),
                ("OH THAT'S ", "BRILLY!!"),
            ]
            let chosen = shouts.randomElement() ?? ("VERY NICE, ", "BRILLY!!")
            self.shoutPrefix = chosen.0
            self.shoutAccent = chosen.1
            self.tag = "!! VERY NICE"
            self.message = pool.randomElement() ?? "Very nice, Brilly!! That sacrifice is pure chess art!"

        case (.blunder, .brillyDer):
            let shouts: [(String, String)] = [
                ("BLUN-", "DER!!"),
                ("OH ", "DERRR!!"),
                ("MAJOR BLUN-", "DER!!"),
                ("OOPS, ", "DERRR!!"),
            ]
            let chosen = shouts.randomElement() ?? ("BLUN-", "DER!!")
            self.shoutPrefix = chosen.0
            self.shoutAccent = chosen.1
            self.tag = "?? BLUN-DER"
            self.message = pool.randomElement() ?? "Blun-DER!! Big derrr energy — we've all been there!"

        case (.brilliant, .cosmicAlien):
            self.shoutPrefix = "BRILLIANT "
            self.shoutAccent = "SIGNAL!!"
            self.tag = "GALAXY-BRAIN"
            self.message = pool.randomElement() ?? "Beam me up, Magnus!"

        case (.blunder, .cosmicAlien):
            self.shoutPrefix = "HULL "
            self.shoutAccent = "BREACH!!"
            self.tag = "ORBIT ALERT"
            self.message = pool.randomElement() ?? "Houston, we dropped a piece."

        case (.brilliant, .standard):
            self.shoutPrefix = "BRILLIANT "
            self.shoutAccent = "MOVE"
            self.tag = "!!"
            self.message = pool.randomElement() ?? "Brilliant sacrifice."

        case (.blunder, .standard):
            self.shoutPrefix = "BLUNDER "
            self.shoutAccent = "DETECTED"
            self.tag = "??"
            self.message = pool.randomElement() ?? "Serious blunder."
        }
    }
}

/// Non-blocking floating toast banner for Brilliant & Blunder moments,
/// supporting the Ghibli Thumbs-Up Buddy (`Brilly/Der`), glowing Diamond (`Standard`),
/// and Cosmic Alien UFO (`Alien UFO`) themes.
public struct AlienCelebrationBanner: View {
    public let event: CelebrationEvent
    public let surfaceStyle: SurfaceStyle
    public let onDismiss: () -> Void

    public init(event: CelebrationEvent, surfaceStyle: SurfaceStyle, onDismiss: @escaping () -> Void) {
        self.event = event
        self.surfaceStyle = surfaceStyle
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let isBril = event.kind == .brilliant
        let accent = isBril ? BrillyPalette.brillyTeal : BrillyPalette.blunderRose

        Button(action: onDismiss) {
            ZStack(alignment: .trailing) {
                // Subtle oversized !! / ?? watermark shimmer on right edge
                Text(isBril ? "!!" : "??")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(accent.opacity(0.11))
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)

                HStack(spacing: 12) {
                    switch event.calloutStyle {
                    case .brillyDer:
                        BrillyGhibliBuddyView(mood: isBril ? .brilliant : .blunder, size: 62)
                    case .cosmicAlien:
                        BrillyAlienUFOView(mood: isBril ? .brilliant : .blunder, size: 66, showBeam: true)
                    case .standard:
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.22))
                                .frame(width: 48, height: 48)
                            if isBril {
                                BrillyGemIcon(size: 26, color: BrillyPalette.brillyTeal)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(BrillyPalette.blunderRose)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(event.tag)
                                .font(.system(size: 9.5, weight: .black, design: .rounded))
                                .tracking(1.1)
                                .foregroundStyle(BrillyPalette.voidBg)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(accent))
                        }

                        // Bold punchy shoutout ("BRILLY!! MOVE!" / "BLUN-DER!!")
                        HStack(spacing: 0) {
                            Text(event.shoutPrefix)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(event.calloutStyle == .brillyDer && isBril ? accent : .white)
                            Text(event.shoutAccent)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(isBril ? Color(hex: 0x67E8F9) : accent)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                        Text(event.message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(hex: 0xE2E8F0))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .brillySurface(surfaceStyle, cornerRadius: 22, tint: accent)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1.2)
            )
            .shadow(color: accent.opacity(0.36), radius: 16, y: 5)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .scale(scale: 0.94)).combined(with: .opacity))
    }
}
