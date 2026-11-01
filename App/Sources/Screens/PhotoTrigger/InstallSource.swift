import StoreKit

/// Where this copy of the app came from, as far as the debug entry cares.
protocol InstallSourceProbe: Sendable {
    func environment() async throws -> AppStore.Environment
}

/// The photo trigger's debug entry shows in development and TestFlight
/// builds and never in an App Store download (handoff 7.5). TestFlight is
/// StoreKit's sandbox environment. A probe that fails -- likely on a
/// simulator or a development build -- shows it: hiding a test tool from
/// a tester is the worse mistake.
enum InstallSource {
    static func showsDebugEntry(isDebugBuild: Bool, probe: InstallSourceProbe) async -> Bool {
        if isDebugBuild { return true }
        do {
            return try await probe.environment() != .production
        } catch {
            return true
        }
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
