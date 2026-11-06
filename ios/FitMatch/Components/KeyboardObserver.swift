import UIKit
import Combine
import SwiftUI

// MARK: - Production-Grade Keyboard Observer for SwiftUI

public final class KeyboardObserver: ObservableObject {
    public static let shared = KeyboardObserver()

    @Published public var keyboardHeight: CGFloat = 0
    @Published public var effectiveKeyboardOffset: CGFloat = 0
    @Published public var isKeyboardVisible: Bool = false
    private var cancellables = Set<AnyCancellable>()

    public var currentBottomSafeArea: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        let window = windowScene?.windows.first(where: { $0.isKeyWindow })
            ?? windowScene?.windows.first
        return window?.safeAreaInsets.bottom ?? 34
    }

    private init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { notification -> (CGFloat, Double)? in
                guard let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return nil }
                let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
                return (frame.height, duration)
            }
            .sink { [weak self] (height, duration) in
                guard let self = self else { return }
                let safeArea = self.currentBottomSafeArea
                let offset = max(0, height - safeArea)
                withAnimation(.easeOut(duration: duration)) {
                    self.keyboardHeight = height
                    self.effectiveKeyboardOffset = offset
                    self.isKeyboardVisible = true
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .compactMap { notification -> Double in
                (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            }
            .sink { [weak self] duration in
                withAnimation(.easeOut(duration: duration)) {
                    self?.keyboardHeight = 0
                    self?.effectiveKeyboardOffset = 0
                    self?.isKeyboardVisible = false
                }
            }
            .store(in: &cancellables)
    }
}
