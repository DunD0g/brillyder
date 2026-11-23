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

public enum BrillyPalette {
    public static let voidBg = Color(hex: 0x070B14)
    public static let hullBg = Color(hex: 0x0F172A)
    public static let brillyTeal = Color(hex: 0x2DD4BF)
    public static let warpPurple = Color(hex: 0xA855F7)
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

    /// WCAG AA+ contrast foreground ink for move classification pills and on-board badges.
    public static func badgeForeground(for classification: MoveClassification) -> Color {
        switch classification {
        case .inaccuracy, .excellent:
            return Color(hex: 0x070B14)
        default:
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
