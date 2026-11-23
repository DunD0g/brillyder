import SwiftUI
import BrillyDerUI
#if canImport(AVFoundation) && os(iOS)
import AVFoundation
#endif

@main
struct BrillyDerApp: App {
    @State private var store = BrillyAppStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Self.configureAudioSessionAsync()
    }

    var body: some Scene {
        WindowGroup {
            BrillyDerRootView()
                .environment(store)
                .environment(\.brillyPieceSet, store.pieceSet)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                store.handleScenePhaseChange(isBackground: true)
            case .active:
                store.handleScenePhaseChange(isBackground: false)
            default:
                break
            }
        }
    }

    private static func configureAudioSessionAsync() {
        #if canImport(AVFoundation) && os(iOS)
        Task.detached(priority: .utility) {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                // Non-fatal: app stays functional even if audio session cannot activate.
            }
        }
        #endif
    }
}
