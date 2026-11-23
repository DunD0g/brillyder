import SwiftUI

/// Glowing Cosmic / Liquid Glass Tractor-Beam progress bar replacing stock thin ProgressView.
public struct TractorBeamProgressBar: View {
    let progress: Double
    let height: CGFloat

    public init(progress: Double, height: CGFloat = 10) {
        self.progress = progress
        self.height = height
    }

    public var body: some View {
        let clamped = max(0.0, min(1.0, progress.isFinite ? progress : 0))

        GeometryReader { geo in
            let fillWidth = clamped <= 0.001
                ? 0
                : min(geo.size.width, max(height, geo.size.width * CGFloat(clamped)))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )

                if fillWidth > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    BrillyPalette.brillyTeal,
                                    Color(hex: 0x06B6D4),
                                    BrillyPalette.warpPurple,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                        .overlay(alignment: .trailing) {
                            Circle()
                                .fill(Color.white.opacity(0.92))
                                .frame(width: height * 0.72, height: height * 0.72)
                                .padding(.trailing, height * 0.16)
                                .shadow(color: BrillyPalette.brillyTeal, radius: 5)
                        }
                        .shadow(color: BrillyPalette.brillyTeal.opacity(0.45), radius: 8, y: 0)
                        .animation(.easeOut(duration: 0.22), value: clamped)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analysis progress")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}
