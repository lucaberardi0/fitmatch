import UIKit
import SwiftUI

// MARK: - Enable Native Interactive Pop Gesture (Swipe to Go Back)
// By default, hiding the system navigation back button (.navigationBarBackButtonHidden(true))
// disables UIKit's interactivePopGestureRecognizer. This extension restores smooth edge-swipe
// back gesture navigation across all NavigationStacks in the app.

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard viewControllers.count > 1 else { return false }
        return transitionCoordinator?.isAnimated != true
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Ensure edge swipe-to-go-back takes priority over nested horizontal scroll views/carousels
        return gestureRecognizer === interactivePopGestureRecognizer
    }
}
