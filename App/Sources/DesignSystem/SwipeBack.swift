import UIKit

/// Every pushed screen hides the system bar and draws its own back button,
/// which also turns off UIKit's edge swipe back. This turns the swipe back
/// on: it pops exactly as each screen's back button does (`path.removeLast()`).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only with a screen to go back to: a swipe on the root screen would
        // leave the stack stuck mid-transition.
        gestureRecognizer !== interactivePopGestureRecognizer || viewControllers.count > 1
    }
}
