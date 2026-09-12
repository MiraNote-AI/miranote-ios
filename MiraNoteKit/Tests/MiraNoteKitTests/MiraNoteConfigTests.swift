import XCTest
@testable import MiraNoteKit

final class MiraNoteConfigTests: XCTestCase {
    func testBackendBaseURLsTargetLocalhostPOCs() {
        XCTAssertEqual(MiraNoteConfig.Backend.textBaseURL.absoluteString, "http://localhost:8001")
        XCTAssertEqual(MiraNoteConfig.Backend.voiceBaseURL.absoluteString, "http://localhost:8005")
    }
}

extension MiraNoteConfigTests {
    /// The shipped build's addresses, asserted directly rather than through
    /// `textBaseURL` and friends: those resolve through `#if` at compile time,
    /// so on a test host the device branch is never built and a wrong hostname
    /// would ship unnoticed.
    func testBetaHostsAreTheTunnelEndpoints() {
        XCTAssertEqual(MiraNoteConfig.Backend.Beta.text.absoluteString, "https://beta-text.miranote.app")
        XCTAssertEqual(MiraNoteConfig.Backend.Beta.image.absoluteString, "https://beta-image.miranote.app")
        XCTAssertEqual(MiraNoteConfig.Backend.Beta.chat.absoluteString, "https://beta-chat.miranote.app")
        XCTAssertEqual(MiraNoteConfig.Backend.Beta.voice.absoluteString, "https://beta-voice.miranote.app")
    }

    func testBetaHostsAreHTTPS() {
        for url in MiraNoteConfig.Backend.Beta.all {
            XCTAssertEqual(url.scheme, "https", "\(url) is not HTTPS")
        }
    }

    /// Cloudflare's free Universal SSL signs `miranote.app` and
    /// `*.miranote.app` and nothing deeper, so `text.beta.miranote.app` fails
    /// the TLS handshake outright. The flat form is not a style preference.
    func testBetaHostsAreOnlyOneLabelDeep() {
        for url in MiraNoteConfig.Backend.Beta.all {
            let host = url.host ?? ""
            XCTAssertEqual(
                host.split(separator: ".").count, 3,
                "\(host) has more labels than the wildcard certificate covers"
            )
            XCTAssertTrue(host.hasSuffix(".miranote.app"), "\(host) is off-domain")
        }
    }

    func testBetaHostsAreDistinct() {
        XCTAssertEqual(Set(MiraNoteConfig.Backend.Beta.all).count, 4)
    }
}
