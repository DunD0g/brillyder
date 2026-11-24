import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Studio Ghibli-inspired cartoony chess-buddy medallion used for the default `Brilly/Der` theme:
/// - Positive / Brilliant / Great / Best / Book moves: cheerful thumbs-up guy ("Very nice, Brilly!!")
/// - Mistake / Blunder moves: comical facepalm guy ("Blun-DER!!")
public struct BrillyGhibliBuddyView: View {
    public let mood: BrillyAlienMood
    public let size: CGFloat

    public init(mood: BrillyAlienMood = .brilliant, size: CGFloat = 68) {
        self.mood = mood
        self.size = size
    }

    private var isNegativeMood: Bool {
        mood == .blunder || mood == .mistake
    }

    private var resourceName: String {
        isNegativeMood ? "brilly_buddy_blunder" : "brilly_buddy_thumbsup"
    }

    private var ringColors: [Color] {
        if isNegativeMood {
            return [BrillyPalette.blunderRose, Color(hex: 0xF97316), BrillyPalette.blunderRose.opacity(0.65)]
        }
        return [BrillyPalette.brillyTeal, Color(hex: 0x67E8F9), BrillyPalette.goldAmber.opacity(0.85)]
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [mood.accentColor.opacity(0.32), mood.accentColor.opacity(0.0)],
                        center: .center,
                        startRadius: size * 0.25,
                        endRadius: size * 0.56
                    )
                )
                .frame(width: size * 1.08, height: size * 1.08)

            Group {
                if let img = Self.loadBundledImage(named: resourceName) {
                    img
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(BrillyPalette.hullBg)
                        Image(systemName: isNegativeMood ? "hand.thumbsdown.fill" : "hand.thumbsup.fill")
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(mood.accentColor)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: ringColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1.8, size * 0.032)
                    )
            )
            .shadow(color: mood.accentColor.opacity(0.38), radius: 8, y: 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    #if canImport(UIKit)
    @MainActor private static var imageCache: [String: UIImage] = [:]

    @MainActor
    private static func loadBundledImage(named name: String) -> Image? {
        if let cached = imageCache[name] {
            return Image(uiImage: cached)
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let uiImage = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        imageCache[name] = uiImage
        return Image(uiImage: uiImage)
    }
    #elseif canImport(AppKit)
    @MainActor private static var imageCache: [String: NSImage] = [:]

    @MainActor
    private static func loadBundledImage(named name: String) -> Image? {
        if let cached = imageCache[name] {
            return Image(nsImage: cached)
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let nsImage = NSImage(contentsOfFile: url.path) else {
            return nil
        }
        imageCache[name] = nsImage
        return Image(nsImage: nsImage)
    }
    #else
    @MainActor
    private static func loadBundledImage(named name: String) -> Image? { nil }
    #endif
}
