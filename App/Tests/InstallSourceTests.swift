import StoreKit
import XCTest
@testable import MiraNote

/// Acceptance C1 and decision 8, after the review of iOS#172: development
/// builds show the debug entry and schedule; a TestFlight build does either
/// only once the tester turns the Settings switch on; an App Store install
/// and a failing probe do neither (fail closed).
final class InstallSourceTests: XCTestCase {
    private struct Probe: InstallSourceProbe {
        let result: Result<AppStore.Environment, Error>
        func environment() async throws -> AppStore.Environment { try result.get() }
    }

    private struct Failure: Error {}

    private func gates(debug: Bool, _ result: Result<AppStore.Environment, Error>) async -> InstallSource.Gates {
        await InstallSource.gates(isDebugBuild: debug, probe: Probe(result: result))
    }

    func testDebugBuildShowsAndSchedules() async {
        let gates = await gates(debug: true, .failure(Failure()))
        XCTAssertTrue(gates.showsDebugEntry)
        XCTAssertTrue(gates.schedulesAutomatically)
        XCTAssertFalse(gates.offersOptIn, "no switch: always on")
    }

    func testDebugBuildIgnoresTheSwitch() async {
        let gates = await gates(debug: true, .success(.production))
        XCTAssertEqual(gates.applying(optedIn: false), gates)
    }

    func testSandboxOffersTheSwitchAndStaysClosedUntilItIsOn() async {
        let gates = await gates(debug: false, .success(.sandbox))
        XCTAssertTrue(gates.offersOptIn)
        XCTAssertFalse(gates.triggerCanShow, "no prompt, no upload before the tester says so")
        XCTAssertFalse(gates.applying(optedIn: false).triggerCanShow)
    }

    func testSandboxOpensWithTheSwitchOn() async {
        let open = await gates(debug: false, .success(.sandbox)).applying(optedIn: true)
        XCTAssertTrue(open.showsDebugEntry)
        XCTAssertTrue(open.schedulesAutomatically)
        XCTAssertFalse(open.isAppStore)
    }

    func testProductionIsClosedWhateverTheSwitch() async {
        let gates = await gates(debug: false, .success(.production))
        XCTAssertFalse(gates.offersOptIn)
        XCTAssertFalse(gates.applying(optedIn: true).triggerCanShow, "a switch left on from TestFlight opens nothing")
    }

    /// Review of iOS#172, point 2: an App Store install whose probe fails
    /// must not show the debug card.
    func testProbeErrorIsClosed() async {
        let gates = await gates(debug: false, .failure(Failure()))
        XCTAssertEqual(gates, .closed)
        XCTAssertFalse(gates.applying(optedIn: true).triggerCanShow)
    }

    func testXcodeEnvironmentInAReleaseBuildIsClosed() async {
        let gates = await gates(debug: false, .success(.xcode))
        XCTAssertEqual(gates, .closed)
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

    func testLaunchArgumentNamesAnInstall() {
        XCTAssertEqual(InstallSource.launchEnvironment(["-TRIGGER-INSTALL", "testflight"]), .sandbox)
        XCTAssertEqual(InstallSource.launchEnvironment(["-TRIGGER-INSTALL", "appstore"]), .production)
        XCTAssertNil(InstallSource.launchEnvironment(["-TRIGGER-INSTALL", "other"]))
        XCTAssertNil(InstallSource.launchEnvironment(["-TRIGGER-INSTALL"]))
        XCTAssertNil(InstallSource.launchEnvironment([]))
    }
}
