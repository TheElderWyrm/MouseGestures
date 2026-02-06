import Foundation
import AppKit

// MARK: - Gesture Search Service
// Single-purpose service for searching and filtering gestures

class GestureSearchService {
    static let shared = GestureSearchService()
    
    private init() {}
    
    // MARK: - Search and Filter
    
    func searchGestures(in gestures: [Gesture], query: String) -> [Gesture] {
        guard !query.isEmpty else { return gestures }
        
        let lowercasedQuery = query.lowercased()
        
        return gestures.filter { gesture in
            // Search in display description
            if gesture.displayDescription.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            // Search in action identifier
            if gesture.actionIdentifier.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            // Search in zone
            if gesture.zone.rawValue.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            // Search in drag modifier
            if gesture.dragModifier.displayName.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            // Search by action name if available
            if let actionDef = GestureConfigurationService.shared.getActionDefinition(for: gesture.actionIdentifier),
               actionDef.name.lowercased().contains(lowercasedQuery) {
                return true
            }
            
            return false
        }
    }
    
    // MARK: - Gesture Organization
    
    func groupGesturesByZone(_ gestures: [Gesture]) -> [ScreenZone: [Gesture]] {
        var grouped: [ScreenZone: [Gesture]] = [:]
        
        for gesture in gestures {
            if grouped[gesture.zone] == nil {
                grouped[gesture.zone] = []
            }
            grouped[gesture.zone]?.append(gesture)
        }
        
        return grouped
    }
    
    func groupGesturesByPlugin(_ gestures: [Gesture]) -> [String: [Gesture]] {
        var grouped: [String: [Gesture]] = [:]
        
        for gesture in gestures {
            let pluginId = gesture.actionIdentifier.split(separator: ".").first.map(String.init) ?? "Unknown"
            if grouped[pluginId] == nil {
                grouped[pluginId] = []
            }
            grouped[pluginId]?.append(gesture)
        }
        
        return grouped
    }
    
    func getEnabledGestures(_ gestures: [Gesture]) -> [Gesture] {
        return gestures.filter { $0.isEnabled }
    }
    
    func getDisabledGestures(_ gestures: [Gesture]) -> [Gesture] {
        return gestures.filter { !$0.isEnabled }
    }
    
    // MARK: - Modifier Description
    
    func modifiersDescription(_ modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("Command ⌘") }
        if modifiers.contains(.control) { parts.append("Control ⌃") }
        if modifiers.contains(.option) { parts.append("Option ⌥") }
        if modifiers.contains(.shift) { parts.append("Shift ⇧") }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }
}
