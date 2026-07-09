import Foundation
import AppKit

// MARK: - HapticFeedbackService
// Single-purpose service for managing haptic feedback settings

class HapticFeedbackService {
    static let shared = HapticFeedbackService()

    private let configuration = Configuration.shared

    private init() {}

    // MARK: - Public Methods

    func isEnabled() -> Bool {
        return configuration.hapticFeedbackEnabled
    }

    func setEnabled(_ enabled: Bool) {
        configuration.hapticFeedbackEnabled = enabled
        configuration.save()

        NotificationCenter.default.post(
            name: Notification.Name("hapticFeedbackSettingChanged"),
            object: nil,
            userInfo: ["enabled": enabled]
        )

        log.log("Haptic feedback \(enabled ? "enabled" : "disabled")")
    }

    func performHapticFeedback() {
        guard isEnabled() else { return }

        // Perform haptic feedback on supported devices
        if #available(macOS 10.11, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .default
            )
        }
    }
}
