import UIKit

/// Every pushed screen hides the system bar and draws its own back button,
/// which also turns off UIKit's edge swipe back. This turns the swipe back
/// on: it pops exactly as each screen's back button does (`path.removeLast()`).
/// The extension applies to every UINavigationController in the process,
/// including system ones such as the camera's UIImagePickerController.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        // Only with a screen to go back to and no push or pop under way, as
        // UIKit's own delegate does: otherwise the stack can get stuck
        // mid-transition.
        return viewControllers.count > 1 && transitionCoordinator == nil
    }
}
