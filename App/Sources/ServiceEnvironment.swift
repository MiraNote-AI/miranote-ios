import MiraNoteKit
import SwiftUI

/// Makes the composition root reachable from any view via
/// `@Environment(\.services)`. Defaults to `.mock` so previews and tests stay
/// offline; `MiraNoteApp` injects `.live`.
private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue: ServiceContainer = .mock
}

extension EnvironmentValues {
    var services: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}
