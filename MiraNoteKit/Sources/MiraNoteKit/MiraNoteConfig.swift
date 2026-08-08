import Foundation

/// Product-level constants. Values that came out of explicit design
/// decisions reference the decision ID from
/// docs/specs/2026-06-10-ios-app-v1-design.md.
public enum MiraNoteConfig {
    /// D1: at most this many images can be added in one picking session.
    public static let maxImagesPerAdd = 3

    /// Backend addresses -- the single place every service URL comes from.
    /// The live ServiceContainer takes these as defaults and tests inject
    /// their own, so pointing the app at a different deployment (cloud,
    /// staging) means editing exactly this enum and nothing else.
    public enum Backend {
        /// Simulator builds and macOS test hosts reach the dev machine's
        /// own loopback (integration spec D5). A real device reaches the
        /// shared beta backend -- the team Mac running start_backends.sh --
        /// over mDNS on the same Wi-Fi (docs/RUN_ON_YOUR_PHONE.md).
        /// The beta host is the Mac's BONJOUR name (scutil --get
        /// LocalHostName + .local) -- NOT its shell hostname; macOS
        /// silently appends -2 after a past name collision here.
        static let host: String = {
            #if targetEnvironment(simulator) || os(macOS)
            "localhost"
            #else
            "Jasons-MacBook-Pro-2.local"
            #endif
        }()

        private static func base(port: Int) -> URL {
            URL(string: "http://\(host):\(port)")!
        }

        /// text-clean-expand POC: /clean, /expand, /polish.
        public static let textBaseURL = base(port: 8001)
        /// voice-to-text POC: /transcribe.
        public static let voiceBaseURL = base(port: 8005)
        /// chatbot POC: /chat.
        public static let chatBaseURL = base(port: 8003)
        /// image-generation POC: /generate, /cutout, /stylize, /border.
        public static let imageBaseURL = base(port: 8002)
    }
}
