import Foundation
import Cocoa

// MARK: - Activation Mapper

/// Central mapper that understands gesture structure and determines which activation types
/// each gesture requires. This removes gesture-awareness from detection plugins, keeping
/// them focused solely on detection.
///
/// This is the ONLY place that knows about gesture field structure and how to map
/// gesture properties to activation types.
class ActivationMapper {
    
    // MARK: - Singleton
    
    static let shared = ActivationMapper()
    
    private init() {}
    
    // MARK: - Gesture → Activation Type Mapping
    
    /// Determine which activation types a gesture requires.
    /// This is the single source of truth for gesture→activation mapping.
    func activationTypes(for gesture: Gesture) -> Set<ActivationType> {
        var types = Set<ActivationType>()
        
        // Modifier keys: Required when gesture has a zone trigger with modifiers
        if gesture.hasZoneTrigger && !gesture.modifiers.isEmpty {
            types.insert(.modifierKey)
        }
        
        // Mouse button: Required when:
        // 1. Gesture has a mouse button trigger (click-based), OR
        // 2. Gesture has drag requirement (button must be held for zone detection)
        if gesture.mouseButtonTrigger != nil {
            types.insert(.mouseButton)
        }
        if gesture.hasZoneTrigger && gesture.dragModifier != .none {
            types.insert(.mouseButton)
        }
        
        // Keyboard shortcut: Required when gesture has keyboard trigger
        if gesture.keyboardTrigger != nil {
            types.insert(.keyboardShortcut)
        }
        
        // Screen zone: Required when gesture has a zone trigger
        if gesture.hasZoneTrigger {
            types.insert(.screenZone)
        }
        
        return types
    }
    
    // MARK: - Gate Validation Helpers
    
    /// Check if held modifiers match any gesture that uses a dependent type.
    func heldModifiersMatchGestures(_ modifiers: NSEvent.ModifierFlags, 
                                    dependentType: ActivationType, 
                                    gestures: [Gesture]) -> Bool {
        if gestures.contains(where: { gesture in
            activationTypes(for: gesture).contains(dependentType) && gesture.modifiers.isEmpty
        }) {
            return true
        }
        
        for gesture in gestures {
            guard activationTypes(for: gesture).contains(dependentType) else { continue }
            if modifiers.contains(gesture.modifiers) {
                return true
            }
        }
        
        return false
    }
    
    /// Check if held mouse button matches any gesture that uses screen zones.
    func heldButtonMatchesGestures(_ button: MouseButtonTrigger.MouseButton,
                                   gestures: [Gesture]) -> Bool {
        let heldDrag = DragModifier.from(mouseButton: button)
        
        for gesture in gestures {
            guard activationTypes(for: gesture).contains(.screenZone) else { continue }
            if gesture.dragModifier == heldDrag || gesture.dragModifier == .none || gesture.dragModifier == .anyDrag {
                return true
            }
        }
        
        return false
    }
}
