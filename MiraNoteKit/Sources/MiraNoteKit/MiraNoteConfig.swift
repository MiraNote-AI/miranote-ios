import CoreGraphics
import Foundation

/// Product-level constants. Values that came out of explicit design
/// decisions reference the decision ID from
/// docs/specs/2026-06-10-ios-app-v1-design.md.
public enum MiraNoteConfig {
    /// D1: at most this many images can be added in one picking session.
    public static let maxImagesPerAdd = 3

    /// The page is a fixed-width column ("width locked", Meng 2026-07-08):
    /// it scrolls down without limit but never changes width, so a page
    /// looks the same on every device and exports exactly as edited.
    ///
    /// Everything that places or measures canvas content resolves to this
    /// one number. Three used to disagree -- content was authored around
    /// 360, the editor board was `device width - 44` (358 on a 402pt
    /// phone, less on smaller ones), and reading/export rendered a fixed
    /// 360 -- so the same page sat differently depending on where you
    /// looked at it.
    ///
    /// It fits every device the app supports: the narrowest is 375pt.
    public static let pageWidth: CGFloat = 360

    /// Backend addresses -- the single place every service URL comes from.
    /// The live ServiceContainer takes these as defaults and tests inject
    /// their own, so pointing the app at a different deployment (cloud,
    /// staging) means editing exactly this enum and nothing else.
    public enum Backend {
        /// Addresses a shipped beta build talks to, through the Cloudflare
        /// tunnel on the team Mac. They replace the old mDNS path, which
        /// needed the phone and the Mac on one Wi-Fi; the backends now bind
        /// loopback and the tunnel is the only way in.
        ///
        /// Named separately rather than only as the `#if` result so a test on
        /// any platform can assert them. On a test host the device branch is
        /// never compiled, and a wrong hostname would otherwise ship unseen.
        ///
        /// One label deep on purpose. Cloudflare's free Universal SSL signs
        /// `miranote.app` and `*.miranote.app` and nothing deeper, so
        /// `text.beta.miranote.app` fails the TLS handshake before a request
        /// is even sent. These are compiled into the shipped build, so
        /// changing one costs every tester a new install.
        public enum Beta {
            public static let text = URL(string: "https://beta-text.miranote.app")!
            public static let image = URL(string: "https://beta-image.miranote.app")!
            public static let chat = URL(string: "https://beta-chat.miranote.app")!
            public static let voice = URL(string: "https://beta-voice.miranote.app")!

            static let all = [text, image, chat, voice]
        }

        /// Simulator builds and macOS test hosts reach the dev machine's own
        /// loopback (integration spec D5). They need the token too: the
        /// backends require it on loopback as well.
        private static func local(port: Int) -> URL {
            URL(string: "http://localhost:\(port)")!
        }

        /// text-clean-expand POC: /clean, /expand, /polish.
        public static let textBaseURL: URL = {
            #if targetEnvironment(simulator) || os(macOS)
            local(port: 8001)
            #else
            Beta.text
            #endif
        }()
        /// voice-to-text POC: /transcribe.
        public static let voiceBaseURL: URL = {
            #if targetEnvironment(simulator) || os(macOS)
            local(port: 8005)
            #else
            Beta.voice
            #endif
        }()
        /// chatbot POC: /chat.
        public static let chatBaseURL: URL = {
            #if targetEnvironment(simulator) || os(macOS)
            local(port: 8003)
            #else
            Beta.chat
            #endif
        }()
        /// image-generation POC: /generate, /cutout, /stylize, /border.
        public static let imageBaseURL: URL = {
            #if targetEnvironment(simulator) || os(macOS)
            local(port: 8002)
            #else
            Beta.image
            #endif
        }()

        /// The beta bearer token, injected at build time from an untracked
        /// xcconfig and read back out of the app's Info.plist.
        ///
        /// Nil in unit tests, which run outside an app bundle, and nil in a
        /// build configured without one. Both then get 401s the app can
        /// explain, which is a better failure than refusing to launch. The
        /// unexpanded placeholder is treated as absent because that is what an
        /// Info.plist carries when the build setting was never defined.
        public static let betaToken: String? = {
            guard let value = Bundle.main.object(forInfoDictionaryKey: "BetaAPIToken") as? String,
                  !value.isEmpty,
                  !value.hasPrefix("$(")
            else { return nil }
            return value
        }()
    }
}
