import Foundation

/// Product-level constants. Values that came out of explicit design
/// decisions reference the decision ID from
/// docs/specs/2026-06-10-ios-app-v1-design.md.
public enum MiraNoteConfig {
    /// D1: at most this many images can be added in one picking session.
    public static let maxImagesPerAdd = 3

    /// Backend POC addresses. Defaults target the iOS Simulator, which
    /// reaches the Mac's localhost directly (integration spec D5). Real-device
    /// networking is out of scope for v1.
    public enum Backend {
        /// text-clean-expand POC: /clean, /expand, /polish.
        public static let textBaseURL = URL(string: "http://localhost:8001")!
        /// voice-to-text POC: /transcribe.
        public static let voiceBaseURL = URL(string: "http://localhost:8000")!
        /// chatbot POC: /chat.
        public static let chatBaseURL = URL(string: "http://localhost:8003")!
    }
}
