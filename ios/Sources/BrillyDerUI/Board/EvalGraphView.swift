import SwiftUI
import BrillyDerCore

/// Interactive SwiftUI Canvas evaluation area graph — tap or drag to scrub directly to any ply.
public struct EvalGraphView: View {
    let plies: [AnalyzedPly]
    let selectedPly: Int
    let onSelectPly: (Int) -> Void

    public init(plies: [AnalyzedPly], selectedPly: Int, onSelectPly: @escaping (Int) -> Void) {
        self.plies = plies
        self.selectedPly = selectedPly
        self.onSelectPly = onSelectPly
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let count = max(1, plies.count)

            Canvas { ctx, size in
                let midY = size.height * 0.5
                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: midY)), with: .color(Color.white.opacity(0.06)))
                ctx.fill(Path(CGRect(x: 0, y: midY, width: size.width, height: midY)), with: .color(Color.black.opacity(0.28)))

                var midLine = Path()
                midLine.move(to: CGPoint(x: 0, y: midY))
                midLine.addLine(to: CGPoint(x: size.width, y: midY))
                ctx.stroke(midLine, with: .color(Color.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                guard !plies.isEmpty else { return }

                if plies.count == 1 {
                    let y = size.height * (1.0 - CGFloat(ChessMath.clamp(plies[0].evalAfter.winPercentWhite / 100.0, min: 0.04, max: 0.96)))
                    let r: CGFloat = 4.5
                    ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.5 - r, y: y - r, width: r * 2, height: r * 2)), with: .color(BrillyPalette.brillyTeal))
                } else {
                    var area = Path()
                    var stroke = Path()

                    for (idx, p) in plies.enumerated() {
                        let x = (CGFloat(idx) / CGFloat(count - 1)) * size.width
                        let y = size.height * (1.0 - CGFloat(ChessMath.clamp(p.evalAfter.winPercentWhite / 100.0, min: 0.02, max: 0.98)))
                        if idx == 0 {
                            area.move(to: CGPoint(x: x, y: size.height))
                            area.addLine(to: CGPoint(x: x, y: y))
                            stroke.move(to: CGPoint(x: x, y: y))
                        } else {
                            area.addLine(to: CGPoint(x: x, y: y))
                            stroke.addLine(to: CGPoint(x: x, y: y))
                        }
                        if idx == plies.count - 1 {
                            area.addLine(to: CGPoint(x: x, y: size.height))
                            area.closeSubpath()
                        }
                    }

                    ctx.fill(area, with: .linearGradient(
                        Gradient(colors: [BrillyPalette.brillyTeal.opacity(0.35), BrillyPalette.brillyTeal.opacity(0.04)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    ))
                    ctx.stroke(stroke, with: .color(BrillyPalette.brillyTeal), lineWidth: 1.8)
                }

                // Key moment markers (Brilliant / Blunder / Mistake)
                for (idx, p) in plies.enumerated() {
                    guard p.classification == .brilliant || p.classification == .blunder || p.classification == .mistake else { continue }
                    let x = count == 1 ? size.width * 0.5 : (CGFloat(idx) / CGFloat(count - 1)) * size.width
                    let y = size.height * (1.0 - CGFloat(ChessMath.clamp(p.evalAfter.winPercentWhite / 100.0, min: 0.05, max: 0.95)))
                    let r: CGFloat = p.classification == .brilliant ? 3.8 : 3.0
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(BrillyPalette.color(for: p.classification)))
                }

                // Active ply cursor
                if selectedPly > 0 && selectedPly <= plies.count {
                    let idx = selectedPly - 1
                    let x = count == 1 ? size.width * 0.5 : (CGFloat(idx) / CGFloat(count - 1)) * size.width
                    var cursor = Path()
                    cursor.move(to: CGPoint(x: x, y: 0))
                    cursor.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(cursor, with: .color(Color.white.opacity(0.85)), lineWidth: 1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        guard !plies.isEmpty, w > 0 else { return }
                        let target: Int
                        if plies.count == 1 {
                            target = 1
                        } else {
                            let ratio = max(0, min(1, val.location.x / w))
                            target = max(1, min(plies.count, Int((ratio * Double(plies.count - 1)).rounded()) + 1))
                        }
                        if target != selectedPly {
                            onSelectPly(target)
                        }
                    }
            )
        }
        .frame(height: 68)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Game evaluation graph")
        .accessibilityValue("Ply \(selectedPly) of \(plies.count)")
    }
}
