import StoreKit

/// Where this copy of the app came from, as far as the debug entry cares.
protocol InstallSourceProbe: Sendable {
    func environment() async throws -> AppStore.Environment
}

/// The photo trigger runs in development builds, in TestFlight builds only
/// once the tester turns it on in Settings, and never in an App Store
/// download (handoff 7.5, decision 8). TestFlight is StoreKit's sandbox
/// environment.
///
/// BEFORE THE FIRST APP STORE RELEASE: the whole feature is off in App Store
/// builds because the AI calls still go to the internal test backend with a
/// teammate passcode, and there is no consent flow or privacy-policy entry
/// yet. When those are in place, turn the App Store case on in
/// `gates(isDebugBuild:probe:)` (decision 11-04).
enum InstallSource {
    /// What this install may do.
    struct Gates: Equatable {
        /// The Home debug card.
        var showsDebugEntry: Bool
        /// Automatic scheduling and the first-launch Photos and notification
        /// prompts.
        var schedulesAutomatically: Bool
        /// A definite App Store install (StoreKit said `.production`): pushes
        /// a TestFlight build left pending are taken back. Never for a
        /// failing probe.
        var isAppStore = false
        /// A TestFlight install: Settings shows the trigger's switch, and
        /// both gates above open only while it is on (`applying(optedIn:)`).
        /// Photos leave the phone only after the tester turned it on.
        var offersOptIn = false

        /// The debug entry or automatic pushes: some way into the story and
        /// its ending can show.
        var triggerCanShow: Bool { showsDebugEntry || schedulesAutomatically }

        static let closed = Gates(showsDebugEntry: false, schedulesAutomatically: false)

        /// These gates with the Settings switch read in: a TestFlight
        /// install opens both while it is on; any other install is as it is.
        func applying(optedIn: Bool) -> Gates {
            guard offersOptIn, optedIn else { return self }
            return Gates(showsDebugEntry: true, schedulesAutomatically: true, offersOptIn: true)
        }
    }

    /// A failing probe -- likely a first launch with no network -- may be an
    /// App Store install: everything stays closed (fail closed).
    static func gates(isDebugBuild: Bool, probe: InstallSourceProbe) async -> Gates {
        if isDebugBuild { return Gates(showsDebugEntry: true, schedulesAutomatically: true) }
        switch try? await probe.environment() {
        case .production?:
            return Gates(showsDebugEntry: false, schedulesAutomatically: false, isAppStore: true)
        case .sandbox?:
            return Gates(showsDebugEntry: false, schedulesAutomatically: false, offersOptIn: true)
        default:
            return .closed
        }
    }

    /// This install's gates: this build, StoreKit's answer -- or, in DEBUG,
    /// `-TRIGGER-INSTALL testflight|appstore` (UI tests of the Settings
    /// switch) answering as that install would.
    static func live() async -> Gates {
        #if DEBUG
        if let environment = launchEnvironment(ProcessInfo.processInfo.arguments) {
            return await gates(isDebugBuild: false, probe: FixedProbe(answer: environment))
        }
        #endif
        return await gates(isDebugBuild: isDebugBuild, probe: AppTransactionProbe())
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    #if DEBUG
    /// The install `-TRIGGER-INSTALL` names, if any.
    static func launchEnvironment(_ arguments: [String]) -> AppStore.Environment? {
        guard let index = arguments.firstIndex(of: "-TRIGGER-INSTALL"), arguments.indices.contains(index + 1)
        else { return nil }
        switch arguments[index + 1] {
        case "testflight": return .sandbox
        case "appstore": return .production
        default: return nil
        }
    }

    private struct FixedProbe: InstallSourceProbe {
        let answer: AppStore.Environment
        func environment() async throws -> AppStore.Environment { answer }
    }
    #endif
}

/// StoreKit 2's signed app transaction: `.sandbox` under TestFlight,
/// `.production` from the App Store, `.xcode` from Xcode.
struct AppTransactionProbe: InstallSourceProbe {
    func environment() async throws -> AppStore.Environment {
        switch try await AppTransaction.shared {
        case .verified(let transaction), .unverified(let transaction, _):
            return transaction.environment
        }
    }
}
