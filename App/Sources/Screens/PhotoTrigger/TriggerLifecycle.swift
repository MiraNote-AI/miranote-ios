import SwiftUI

/// Hooks the photo trigger's scheduler to the scene: it plans when the app
/// comes to the front (and on first appearance) and hears of the background.
/// `enabled` is `InstallSource.Gates.schedulesAutomatically` -- a definite
/// development or TestFlight answer only (decision 8, fail closed); an App
/// Store install, or one whose probe failed, does nothing new.
private struct TriggerLifecycle: ViewModifier {
    let controller: TriggerController
    let enabled: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // First appearance (or the gate opening): the scene is already
            // active, so no phase change fires. The run starts unstructured,
            // like a phase change's: cancelling this task (the view going)
            // must not cut a run short mid-wave.
            .task(id: enabled) {
                if enabled, scenePhase == .active { Task { await controller.sceneBecameActive() } }
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
