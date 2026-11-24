import SwiftUI
import BrillyDerCore

public enum SurfaceStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case liquidGlass = "liquidGlass"
    case cosmic = "cosmic"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .cosmic: return "Cosmic Minimalist"
        }
    }

    public var subtitle: String {
        switch self {
        case .liquidGlass: return "iOS 26 optical lensing & floating glass"
        case .cosmic: return "Deep space hull & dark glassmorphism"
        }
    }
}

public enum VibeMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case cosmic
    case classic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cosmic: return "Cosmic"
        case .classic: return "Classic"
        }
    }
}

public enum CalloutStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case brillyDer = "brillyDer"
    case standard = "standard"
    case cosmicAlien = "cosmicAlien"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .brillyDer: return "Brilly/Der"
        case .standard: return "Standard"
        case .cosmicAlien: return "Alien UFO"
        }
    }

    public var subtitle: String {
        switch self {
        case .brillyDer: return "Expressive emoji badges shouting \"Very nice, Brilly!!\" & \"Blun-DER!!\""
        case .standard: return "Clean diamond & classic tournament chess callouts"
        case .cosmicAlien: return "Cosmic Alien UFO mascot & space-probe alerts"
        }
    }
}

/// Selectable emoji pairs for the default `Brilly/Der` toast & share card medallions.
public enum BrillyEmojiPack: String, Codable, CaseIterable, Sendable, Identifiable {
    case mindBlown = "mindBlown"
    case fireSkull = "fireSkull"
    case thumbsClown = "thumbsClown"
    case crownMelting = "crownMelting"

    public var id: String { rawValue }

    public var brilliantEmoji: String {
        switch self {
        case .mindBlown:    return "🤯"
        case .fireSkull:    return "🔥"
        case .thumbsClown:  return "👍"
        case .crownMelting: return "👑"
        }
    }

    public var blunderEmoji: String {
        switch self {
        case .mindBlown:    return "🤦"
        case .fireSkull:    return "💀"
        case .thumbsClown:  return "🤡"
        case .crownMelting: return "🫠"
        }
    }

    public var title: String {
        switch self {
        case .mindBlown:    return "Mind-Blown"
        case .fireSkull:    return "Cooked"
        case .thumbsClown:  return "Very Nice"
        case .crownMelting: return "Royal Melt"
        }
    }

    public var pairLabel: String {
        "\(brilliantEmoji) / \(blunderEmoji)"
    }
}

/// Non-destructive display-time player name masking modes (exclusive to Founder Admin Creator Studio).
public enum CreatorNameMaskMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case off = "off"
    case blurred = "blurred"
    case anonymous = "anonymous"
    case brillyFun = "brillyFun"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off:       return "Off"
        case .blurred:   return "Blur"
        case .anonymous: return "Anon"
        case .brillyFun: return "Brilly Fun"
        }
    }

    public var subtitle: String {
        switch self {
        case .off:       return "Show real usernames"
        case .blurred:   return "Blur usernames cleanly for screen recordings"
        case .anonymous: return "Replace with You / Opponent (or White / Black)"
        case .brillyFun: return "Consistent funny Brilly/Der chess aliases"
        }
    }
}

/// Optional broadcast/exhibition visual theme overlay (exclusive to Founder Admin Creator Studio).
public enum CreatorExhibitionTheme: String, Codable, CaseIterable, Sendable, Identifiable {
    case none = "none"
    case worldChampionship = "worldChampionship"
    case rapidBlitz = "rapidBlitz"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none:              return "Off"
        case .worldChampionship: return "WCC Gold"
        case .rapidBlitz:        return "Rapid & Blitz"
        }
    }

    public var accentColor: Color {
        switch self {
        case .none:              return BrillyPalette.brillyTeal
        case .worldChampionship: return Color(hex: 0xF59E0B)
        case .rapidBlitz:        return Color(hex: 0x22D3EE)
        }
    }

    public var secondaryAccent: Color {
        switch self {
        case .none:              return BrillyPalette.warpPurple
        case .worldChampionship: return Color(hex: 0xFDE68A)
        case .rapidBlitz:        return Color(hex: 0xA855F7)
        }
    }

    public var defaultRibbonLabel: String {
        switch self {
        case .none:              return ""
        case .worldChampionship: return "WORLD CHAMPIONSHIP 2026"
        case .rapidBlitz:        return "WORLD RAPID & BLITZ 2026"
        }
    }
}

/// Deterministic display-time player name masker so usernames stay consistent across a game
/// without mutating saved PGNs or vault records.
public enum CreatorNameMasker {
    public static let funAliases: [String] = [
        "Capt. Blun-DER",
        "Sir Hangs-a-Lot",
        "GM GalaxyBrain",
        "Queen Sac Enjoyer",
        "En Passant Bandit",
        "Forklift Certified",
        "Tunnel Vision 1200",
        "Dr. Brilly",
        "Rook Lift Legend",
        "Back-Rank Victim",
        "Tempo Goblin",
        "Premove Gambler",
        "Knight Fork Ninja",
        "Bongcloud Scholar",
        "Flagging Machine",
        "Mouseslip Prodigy",
    ]

    public static func mask(
        rawName: String,
        opponentRawName: String? = nil,
        side: PieceColor,
        mode: CreatorNameMaskMode,
        userHandles: [String]
    ) -> (text: String, isBlurred: Bool) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? (side == .white ? "White" : "Black") : trimmed

        switch mode {
        case .off:
            return (fallback, false)
        case .blurred:
            return (fallback, true)
        case .anonymous:
            let loweredHandles = Set(userHandles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
            if !loweredHandles.isEmpty {
                if loweredHandles.contains(fallback.lowercased()) {
                    return ("You", false)
                }
                if let opp = opponentRawName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                   loweredHandles.contains(opp) {
                    return ("Opponent", false)
                }
            }
            return (side == .white ? "White" : "Black", false)
        case .brillyFun:
            let idx = stableIndex(for: fallback)
            if let opp = opponentRawName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !opp.isEmpty,
               opp.lowercased() != fallback.lowercased(),
               stableIndex(for: opp) == idx,
               side == .black {
                return (funAliases[(idx + 1) % funAliases.count], false)
            }
            return (funAliases[idx], false)
        }
    }

    private static func stableIndex(for name: String) -> Int {
        // Deterministic 64-bit FNV-1a hash (consistent across app launches, unlike Swift Hasher)
        var hash: UInt64 = 14695981039346656037
        for byte in name.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash % UInt64(funAliases.count))
    }

    /// Parses `[Event "..."]` and `[Round "..."]` from a PGN string for automatic broadcast ribbons.
    public static func extractPgnBroadcastLabel(from pgn: String?) -> String? {
        guard let pgn, !pgn.isEmpty else { return nil }
        func tagValue(_ key: String) -> String? {
            let needle = "[\(key) \""
            guard let startRange = pgn.range(of: needle) else { return nil }
            let rest = pgn[startRange.upperBound...]
            guard let endQuote = rest.firstIndex(of: "\"") else { return nil }
            let val = rest[..<endQuote].trimmingCharacters(in: .whitespacesAndNewlines)
            return val.isEmpty || val == "?" || val == "-" ? nil : val
        }
        guard let event = tagValue("Event") else { return nil }
        let lower = event.lowercased()
        // Skip generic online ladder headers so WCC / Rapid & Blitz fallback looks crisp
        if lower.hasPrefix("rated ") || lower.hasPrefix("casual ") || lower == "live chess" || lower == "online game" {
            return nil
        }
        if let round = tagValue("Round") {
            return "\(event.uppercased()) · RD \(round.uppercased())"
        }
        return event.uppercased()
    }
}

public enum BoardThemeID: String, Codable, CaseIterable, Sendable, Identifiable {
    case slate
    case emerald
    case walnut
    case neon

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .slate: return "Slate"
        case .emerald: return "Emerald"
        case .walnut: return "Walnut"
        case .neon: return "Neon"
        }
    }

    public var lightSquare: Color {
        switch self {
        case .slate:   return Color(hex: 0x9CB0C7)
        case .emerald: return Color(hex: 0xE7EFDC)
        case .walnut:  return Color(hex: 0xECD7B6)
        case .neon:    return Color(hex: 0x2B3550)
        }
    }

    public var darkSquare: Color {
        switch self {
        case .slate:   return Color(hex: 0x4C647D)
        case .emerald: return Color(hex: 0x527D58)
        case .walnut:  return Color(hex: 0x8B5D3D)
        case .neon:    return Color(hex: 0x111827)
        }
    }

    public var lastMove: Color {
        switch self {
        case .slate:   return Color(hex: 0x22D3EE).opacity(0.38)
        case .emerald: return Color(hex: 0xFACC15).opacity(0.48)
        case .walnut:  return Color(hex: 0xFB923C).opacity(0.50)
        case .neon:    return Color(hex: 0xA855F7).opacity(0.55)
        }
    }

    public var selected: Color {
        switch self {
        case .slate:   return Color(hex: 0x10B981).opacity(0.52)
        case .emerald: return Color(hex: 0x10B981).opacity(0.52)
        case .walnut:  return Color(hex: 0xB45309).opacity(0.55)
        case .neon:    return Color(hex: 0x22D3EE).opacity(0.45)
        }
    }

    public var accent: Color {
        switch self {
        case .slate:   return Color(hex: 0x2DD4BF)
        case .emerald: return Color(hex: 0x34D399)
        case .walnut:  return Color(hex: 0xF59E0B)
        case .neon:    return Color(hex: 0xE879F9)
        }
    }

    /// High-contrast coordinate label ink on both light and dark squares (especially Neon).
    public func coordColor(isLightSquare: Bool) -> Color {
        if self == .neon {
            return isLightSquare ? Color(hex: 0xCBD5E1).opacity(0.85) : Color(hex: 0x94A3B8).opacity(0.88)
        }
        return (isLightSquare ? darkSquare : lightSquare).opacity(0.90)
    }
}

public enum PieceSetID: String, Codable, CaseIterable, Sendable, Identifiable {
    case cburnett
    case chessnut
    case spatial
    case kiwen

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cburnett: return "Classic"
        case .chessnut: return "Chessnut"
        case .spatial:  return "Spatial"
        case .kiwen:    return "Minimal"
        }
    }

    public var subtitle: String {
        switch self {
        case .cburnett: return "Tournament standard"
        case .chessnut: return "Bold modern Staunton"
        case .spatial:  return "Sculpted 3D shading"
        case .kiwen:    return "Clean flat geometric"
        }
    }
}

private struct BrillyPieceSetKey: EnvironmentKey {
    static let defaultValue: PieceSetID = .cburnett
}

public extension EnvironmentValues {
    var brillyPieceSet: PieceSetID {
        get { self[BrillyPieceSetKey.self] }
        set { self[BrillyPieceSetKey.self] = newValue }
    }
}

public enum BrillyPalette {
    public static let voidBg = Color(hex: 0x070B14)
    public static let hullBg = Color(hex: 0x0F172A)
    public static let brillyTeal = Color(hex: 0x2DD4BF)
    public static let warpPurple = Color(hex: 0xA855F7)
    public static let warpPurpleText = Color(hex: 0xC084FC)
    public static let blunderRose = Color(hex: 0xFB7185)
    public static let goldAmber = Color(hex: 0xF59E0B)
    public static let inkPrimary = Color(hex: 0xF8FAFC)
    public static let inkSecondary = Color(hex: 0x94A3B8)

    public static func color(for classification: MoveClassification) -> Color {
        switch classification {
        case .brilliant:  return Color(hex: 0x06B6D4)
        case .great:      return Color(hex: 0x3B82F6)
        case .best:       return Color(hex: 0x22C55E)
        case .excellent:  return Color(hex: 0x84CC16)
        case .inaccuracy: return Color(hex: 0xEAB308)
        case .mistake:    return Color(hex: 0xF97316)
        case .blunder:    return Color(hex: 0xEF4444)
        case .book:       return Color(hex: 0xD97706)
        }
    }

    /// WCAG AA+ contrast foreground ink (5.7:1–9.1:1) for move classification pills and on-board badges.
    public static func badgeForeground(for classification: MoveClassification) -> Color {
        switch classification {
        case .brilliant, .best, .excellent, .inaccuracy, .mistake, .book:
            return Color(hex: 0x070B14)
        case .great, .blunder:
            return .white
        }
    }

    public static func color(for arrow: ArrowKind) -> Color {
        switch arrow {
        case .plan:    return brillyTeal.opacity(0.85)
        case .best:    return Color(hex: 0x22C55E).opacity(0.88)
        case .threat:  return blunderRose.opacity(0.88)
        case .outpost: return warpPurple.opacity(0.88)
        }
    }
}

public extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
