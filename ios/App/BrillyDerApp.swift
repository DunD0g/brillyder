import SwiftUI
import BrillyDerUI
#if canImport(AVFoundation) && os(iOS)
import AVFoundation
#endif

@main
struct BrillyDerApp: App {
    @State private var store = BrillyAppStore()

    init() {
        Self.configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            BrillyDerRootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }

    private static func configureAudioSession() {
        #if canImport(AVFoundation) && os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Non-fatal: app stays functional even if audio session cannot activate.
        }
        #endif
    }
}
