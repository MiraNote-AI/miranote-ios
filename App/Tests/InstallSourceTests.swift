import StoreKit
import XCTest
@testable import MiraNote

/// Acceptance C1 and decision 8: the debug entry shows in development and
/// TestFlight builds, never from the App Store, and a failing probe shows
/// it (fail open); automatic scheduling and the first-launch prompts need a
/// definite development or TestFlight answer (fail closed).
final class InstallSourceTests: XCTestCase {
    private struct Probe: InstallSourceProbe {
        let result: Result<AppStore.Environment, Error>
        func environment() async throws -> AppStore.Environment { try result.get() }
    }

    private struct Failure: Error {}

    private func gates(debug: Bool, _ result: Result<AppStore.Environment, Error>) async -> InstallSource.Gates {
        await InstallSource.gates(isDebugBuild: debug, probe: Probe(result: result))
    }

    func testDebugBuildShows() async {
        let shows = await gates(debug: true, .success(.production)).showsDebugEntry
        XCTAssertTrue(shows)
    }

    func testSandboxShows() async {
        let shows = await gates(debug: false, .success(.sandbox)).showsDebugEntry
        XCTAssertTrue(shows)
    }

    func testProductionHides() async {
        let shows = await gates(debug: false, .success(.production)).showsDebugEntry
        XCTAssertFalse(shows)
    }

    func testProbeErrorShows() async {
        let shows = await gates(debug: false, .failure(Failure())).showsDebugEntry
        XCTAssertTrue(shows)
    }

    func testDebugBuildSchedules() async {
        let schedules = await gates(debug: true, .failure(Failure())).schedulesAutomatically
        XCTAssertTrue(schedules)
    }

    func testSandboxSchedules() async {
        let schedules = await gates(debug: false, .success(.sandbox)).schedulesAutomatically
        XCTAssertTrue(schedules)
    }

    func testProductionDoesNotSchedule() async {
        let schedules = await gates(debug: false, .success(.production)).schedulesAutomatically
        XCTAssertFalse(schedules)
    }

    func testProbeErrorDoesNotSchedule() async {
        let schedules = await gates(debug: false, .failure(Failure())).schedulesAutomatically
        XCTAssertFalse(schedules, "an unknown install source asks nothing and schedules nothing")
    }

    /// Only a definite App Store answer takes pending pushes back.
    func testOnlyProductionIsAppStore() async {
        let production = await gates(debug: false, .success(.production)).isAppStore
        let sandbox = await gates(debug: false, .success(.sandbox)).isAppStore
        let failed = await gates(debug: false, .failure(Failure())).isAppStore
        let debug = await gates(debug: true, .success(.production)).isAppStore
        XCTAssertTrue(production)
        XCTAssertFalse(sandbox)
        XCTAssertFalse(failed, "a failing probe may be TestFlight: its pushes stay")
        XCTAssertFalse(debug)
    }
}
