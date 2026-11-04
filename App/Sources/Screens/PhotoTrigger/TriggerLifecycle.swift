import SwiftUI

/// Hooks the photo trigger's scheduler to the scene: it plans when the app
/// comes to the front (and on first appearance) and hears of the background.
/// `enabled` is the debug-entry gate -- development and TestFlight builds only
/// (decision 8); an App Store install does nothing new.
private struct TriggerLifecycle: ViewModifier {
    let controller: TriggerController
    let enabled: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // First appearance (or the gate opening): the scene is already
            // active, so no phase change fires.
            .task(id: enabled) {
                if enabled, scenePhase == .active { await controller.sceneBecameActive() }
            }
            .onChange(of: scenePhase) {
                guard enabled else { return }
                switch scenePhase {
                case .active: Task { await controller.sceneBecameActive() }
                case .background: controller.sceneEnteredBackground()
                default: break
                }
            }
    }
}

extension View {
    func triggerLifecycle(_ controller: TriggerController, enabled: Bool) -> some View {
        modifier(TriggerLifecycle(controller: controller, enabled: enabled))
    }
}
