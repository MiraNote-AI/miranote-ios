import StoreKit
import XCTest
@testable import MiraNote

/// Acceptance C1: the debug entry shows in development and TestFlight
/// builds, never from the App Store; a failing probe shows it.
final class InstallSourceTests: XCTestCase {
    private struct Probe: InstallSourceProbe {
        let result: Result<AppStore.Environment, Error>
        func environment() async throws -> AppStore.Environment { try result.get() }
    }

    private struct Failure: Error {}

    func testDebugBuildShows() async {
        let shows = await InstallSource.showsDebugEntry(isDebugBuild: true, probe: Probe(result: .success(.production)))
        XCTAssertTrue(shows)
    }

    func testSandboxShows() async {
        let shows = await InstallSource.showsDebugEntry(isDebugBuild: false, probe: Probe(result: .success(.sandbox)))
        XCTAssertTrue(shows)
    }

    func testProductionHides() async {
        let probe = Probe(result: .success(.production))
        let shows = await InstallSource.showsDebugEntry(isDebugBuild: false, probe: probe)
        XCTAssertFalse(shows)
    }

    func testProbeErrorShows() async {
        let shows = await InstallSource.showsDebugEntry(isDebugBuild: false, probe: Probe(result: .failure(Failure())))
        XCTAssertTrue(shows)
    }
}
