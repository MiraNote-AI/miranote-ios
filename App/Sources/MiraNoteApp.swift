import MiraNoteKit
import SwiftUI

@main
struct MiraNoteApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.services, Self.services)
        }
    }

    /// UI tests run against offline mocks so they never depend on a live
    /// backend; everything else uses the live wiring.
    private static var services: ServiceContainer {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITEST") { return .mock }
        #endif
        return .live
    }
}

/// App root. In DEBUG a launch argument (`-MIRANOTE_SCREEN <id>`) or the
/// matching environment variable pins a single Flow 7 scene so the QA harness
/// can snapshot each one deterministically; otherwise the app opens on Home.
struct RootView: View {
    var body: some View {
        #if DEBUG
        if let scene = Self.requestedScene {
            if scene == .chat, Self.chatLive {
                MiraChatView(
                    service: ServiceContainer.live.chat,
                    seed: "Sunny afternoon, tiny noodle shop by the bridge"
                )
            } else {
                scene.view
            }
        } else {
            HomeFlow()
        }
        #else
        HomeFlow()
        #endif
    }

    #if DEBUG
    private static var requestedScene: FlowScene? {
        let env = ProcessInfo.processInfo.environment["MIRANOTE_SCREEN"]
        let defaults = UserDefaults.standard.string(forKey: "MIRANOTE_SCREEN")
        guard let raw = env ?? defaults else { return nil }
        return FlowScene(rawValue: raw)
    }

    /// When set, the `chat` catalog scene talks to the live `:8003` backend
    /// instead of the mock -- for eyeballing real replies.
    private static var chatLive: Bool {
        ProcessInfo.processInfo.environment["MIRANOTE_CHAT_LIVE"] != nil
            || UserDefaults.standard.bool(forKey: "MIRANOTE_CHAT_LIVE")
    }
    #endif
}
