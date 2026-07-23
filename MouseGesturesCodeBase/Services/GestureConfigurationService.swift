import Foundation
import SwiftUI

// MARK: - GestureConfigurationService
// Manages gesture configuration operations

class GestureConfigurationService {
    static let shared = GestureConfigurationService()

    private let configuration = Configuration.shared

    private init() {}

    // MARK: - Gesture Management

    func addGesture(_ gesture: Gesture) -> Bool {
        var gestures = configuration.gestures

        // Check for trigger conflicts (same zone + modifiers + drag)
        if let existingIndex = gestures.firstIndex(where: { $0.triggerKey == gesture.triggerKey }) {
            log.log("Gesture trigger conflict detected at index \(existingIndex) (\(gestures[existingIndex].displayDescription))")
            return false
        }

        gestures.append(gesture)
        configuration.gestures = gestures
        configuration.save()

        log.log("Added gesture: \(gesture.displayDescription)")
        return true
    }

    func updateGesture(oldGesture: Gesture, newGesture: Gesture) -> Bool {
        var gestures = configuration.gestures

        // Find the old gesture
        guard let index = gestures.firstIndex(where: { $0.id == oldGesture.id }) else {
            log.log("Gesture not found for update: \(oldGesture.id)")
            return false
        }

        // Check if new gesture trigger would conflict with others (excluding the one being updated)
        if oldGesture.triggerKey != newGesture.triggerKey {
            if gestures.contains(where: { $0.triggerKey == newGesture.triggerKey }) {
                log.log("Update would create trigger conflict with existing gesture")
                return false
            }
        }

        gestures[index] = newGesture
        configuration.gestures = gestures
        configuration.save()

        log.log("Updated gesture: \(oldGesture.displayDescription) -> \(newGesture.displayDescription)")
        return true
    }

    func removeGesture(_ gesture: Gesture) -> Bool {
        var gestures = configuration.gestures

        guard let index = gestures.firstIndex(where: { $0.id == gesture.id }) else {
            log.log("Gesture not found for removal: \(gesture.id)")
            return false
        }

        gestures.remove(at: index)
        configuration.gestures = gestures
        configuration.save()

        log.log("Removed gesture: \(gesture.displayDescription)")
        return true
    }

    func clearAllGestures() {
        configuration.gestures = []
        configuration.save()
        log.log("Cleared all gestures")
    }

    func replaceAllGestures(_ gestures: [Gesture]) {
        configuration.gestures = gestures
        configuration.save()
        log.log("Replaced gestures with \(gestures.count) template gestures")
    }

    func isGestureConflicting(_ gesture: Gesture) -> Bool {
        return configuration.gestures.contains { $0.triggerKey == gesture.triggerKey }
    }

    // MARK: - Default Profiles

    func importDefaultProfile(type: DefaultProfileType) -> ConfigurationProfile? {
        guard let profile = DefaultProfiles.getProfile(for: type) else {
            log.log("Default profile not found for type: \(type)")
            return nil
        }

        // Check for name conflicts and adjust
        var importName = profile.name
        var counter = 2
        while configuration.profiles.contains(where: { $0.name == importName }) {
            importName = "\(profile.name) \(counter)"
            counter += 1
        }

        var newProfile = profile
        newProfile.name = importName
        newProfile.id = UUID()
        newProfile.isDefault = false

        configuration.profiles.append(newProfile)
        configuration.save()

        NotificationCenter.default.post(name: .profilesDidChange, object: nil)

        log.log("Imported default profile: \(newProfile.name)")
        return newProfile
    }

    func resetToDefaults() {
        // Clear all profiles and add default one
        let defaultProfile = ConfigurationProfile(
            name: "Default",
            gestures: DefaultProfiles.createWindowManagementProfile().gestures,
            isDefault: true
        )

        configuration.profiles = [defaultProfile]
        configuration.activeProfileId = defaultProfile.id
        configuration.save()

        NotificationCenter.default.post(name: .profilesDidChange, object: nil)

        log.log("Reset to default configuration")
    }

    // MARK: - Available Actions

    func getAvailableActions() -> [String: [PluginAction]] {
        // Group actions by category
        var grouped: [String: [PluginAction]] = [:]
        for (_, action) in PluginManager.shared.getAllActions() {
            let category = "General" // Default category since PluginAction doesn't have category
            if grouped[category] == nil {
                grouped[category] = []
            }
            grouped[category]?.append(action)
        }
        return grouped
    }

    func getActionDefinition(for identifier: String) -> PluginAction? {
        return PluginManager.shared.getAction(identifier: identifier)?.action
    }

    // MARK: - Gesture Validation

    func validateGesture(_ gesture: Gesture) -> (valid: Bool, error: String?) {
        // Check if action identifier is valid
        if getActionDefinition(for: gesture.actionIdentifier) == nil {
            return (false, "Invalid action identifier: \(gesture.actionIdentifier)")
        }

        // Check for zone validity
        let validZones: [ScreenZone] = [
            .top, .bottom, .left, .right,
            .topLeft, .topRight, .bottomLeft, .bottomRight
        ]

        if !validZones.contains(gesture.zone) {
            return (false, "Invalid zone: \(gesture.zone)")
        }

        // Check activation settings
        if gesture.genericActivation.hasConfig(for: "keyboard_detector") && gesture.keyboardTrigger == nil {
            return (false, "Keyboard activation enabled but no trigger defined")
        }

        if gesture.genericActivation.hasConfig(for: "mouse_button_detector") && gesture.mouseButtonTrigger == nil {
            return (false, "Mouse button activation enabled but no trigger defined")
        }

        // Check timing settings
        if gesture.timing.repeatInterval <= 0 {
            return (false, "Invalid repeat interval")
        }

        if gesture.timing.longPressThreshold <= 0 {
            return (false, "Invalid long press threshold")
        }

        return (true, nil)
    }

    // MARK: - Gesture Grouping

    func getGesturesGroupedByZone() -> [ScreenZone: [Gesture]] {
        var grouped: [ScreenZone: [Gesture]] = [:]

        for gesture in configuration.gestures {
            if grouped[gesture.zone] == nil {
                grouped[gesture.zone] = []
            }
            grouped[gesture.zone]?.append(gesture)
        }

        return grouped
    }

    func getGesturesGroupedByAction() -> [String: [Gesture]] {
        var grouped: [String: [Gesture]] = [:]

        for gesture in configuration.gestures {
            let actionId = gesture.actionIdentifier
            if grouped[actionId] == nil {
                grouped[actionId] = []
            }
            grouped[actionId]?.append(gesture)
        }

        return grouped
    }

    // MARK: - Gesture Search

    func searchGestures(query: String) -> [Gesture] {
        let lowercasedQuery = query.lowercased()

        return configuration.gestures.filter { gesture in
            // Search in display description
            if gesture.displayDescription.lowercased().contains(lowercasedQuery) {
                return true
            }

            // Search in action identifier
            if gesture.actionIdentifier.lowercased().contains(lowercasedQuery) {
                return true
            }

            // Search in zone name
            if gesture.zone.rawValue.lowercased().contains(lowercasedQuery) {
                return true
            }

            // Search in action definition if available
            if let actionDef = getActionDefinition(for: gesture.actionIdentifier) {
                if actionDef.name.lowercased().contains(lowercasedQuery) ||
                   actionDef.description.lowercased().contains(lowercasedQuery) {
                    return true
                }
            }

            return false
        }
    }
}
