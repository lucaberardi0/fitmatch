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
        return viewControllers.count > 1
    }
}
