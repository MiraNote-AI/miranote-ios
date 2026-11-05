import StoreKit

/// Where this copy of the app came from, as far as the debug entry cares.
protocol InstallSourceProbe: Sendable {
    func environment() async throws -> AppStore.Environment
}

/// The photo trigger runs in development and TestFlight builds and never in
/// an App Store download (handoff 7.5, decision 8). TestFlight is StoreKit's
/// sandbox environment.
///
/// BEFORE THE FIRST APP STORE RELEASE: the whole feature is off in App Store
/// builds because the AI calls still go to the internal test backend with a
/// teammate passcode. When the production backend is in place, turn the App
/// Store case on in `gates(isDebugBuild:probe:)` (decision 11-04).
enum InstallSource {
    /// What this install may do.
    struct Gates: Equatable {
        /// The Home debug card. A probe that fails -- likely on a simulator
        /// or a development build -- shows it: hiding a test tool from a
        /// tester is the worse mistake (fail open, as in phase 1).
        var showsDebugEntry: Bool
        /// Automatic scheduling and the first-launch Photos and notification
        /// prompts. These reach real users, so they need a definite
        /// development or TestFlight answer: a failing probe keeps them off
        /// (fail closed).
        var schedulesAutomatically: Bool
        /// A definite App Store install (StoreKit said `.production`): pushes
        /// a TestFlight build left pending are taken back. Never for a
        /// failing probe.
        var isAppStore = false

        /// The debug entry or automatic pushes: some way into the story and
        /// its ending can show.
        var triggerCanShow: Bool { showsDebugEntry || schedulesAutomatically }

        static let closed = Gates(showsDebugEntry: false, schedulesAutomatically: false)
    }

    static func gates(isDebugBuild: Bool, probe: InstallSourceProbe) async -> Gates {
        if isDebugBuild { return Gates(showsDebugEntry: true, schedulesAutomatically: true) }
        do {
            let testing = try await probe.environment() != .production
            return Gates(showsDebugEntry: testing, schedulesAutomatically: testing, isAppStore: !testing)
        } catch {
            return Gates(showsDebugEntry: true, schedulesAutomatically: false)
        }
    }

    /// This install's gates: this build, StoreKit's answer.
    static func live() async -> Gates {
        await gates(isDebugBuild: isDebugBuild, probe: AppTransactionProbe())
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
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
