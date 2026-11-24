import SwiftUI
import BrillyDerCore

/// Sleek animated evaluation bar showing White vs Black advantage with numeric readout.
public struct EvalBarView: View {
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 24
    let score: EngineScore
    let orientation: PieceColor

    public init(score: EngineScore, orientation: PieceColor = .white) {
        self.score = score
        self.orientation = orientation
    }

    public var body: some View {
        let whiteFraction = CGFloat(ChessMath.clamp(score.winPercentWhite / 100.0, min: 0.04, max: 0.96))
        let leftFraction = orientation == .white ? whiteFraction : (1.0 - whiteFraction)
        let leftColor: Color = orientation == .white ? Color(hex: 0xF1F5F9) : Color(hex: 0x1E293B)
        let rightColor: Color = orientation == .white ? Color(hex: 0x1E293B) : Color(hex: 0xF1F5F9)

        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    leftColor
                        .frame(width: geo.size.width * leftFraction)
                    rightColor
                }
                .animation(.spring(duration: 0.35), value: leftFraction)

                HStack {
                    Text(score.display)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(score.cpWhite >= 0 ? Color(hex: 0x0F172A) : Color(hex: 0xF8FAFC))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill((score.cpWhite >= 0 ? Color.white : Color(hex: 0x0F172A)).opacity(0.75))
                        )
                    Spacer()
                }
                .padding(.horizontal, 6)
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .frame(height: max(22, barHeight))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position evaluation \(score.display)")
    }
}
