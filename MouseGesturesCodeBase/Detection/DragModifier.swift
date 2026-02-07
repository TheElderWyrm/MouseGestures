import Foundation

// Enum for drag modifiers (mouse button states)
enum DragModifier: String, Codable, CaseIterable {
    case none = "None"
    case leftDrag = "Left Drag"
    case rightDrag = "Right Drag"
    case middleDrag = "Middle Drag"
    
    var displayName: String {
        switch self {
        case .none: return ""
        case .leftDrag: return "Left Drag"
        case .rightDrag: return "Right Drag"
        case .middleDrag: return "Middle Drag"
        }
    }
    
    // MARK: - MouseButton Conversion
    
    /// The mouse button that must be held for this drag modifier.
    /// Returns nil for `.none`.
    var correspondingMouseButton: MouseButtonTrigger.MouseButton? {
        switch self {
        case .none: return nil
        case .leftDrag: return .left
        case .rightDrag: return .right
        case .middleDrag: return .middle
        }
    }
    
    /// Create a DragModifier from a held mouse button.
    static func from(mouseButton: MouseButtonTrigger.MouseButton) -> DragModifier {
        switch mouseButton {
        case .left: return .leftDrag
        case .right: return .rightDrag
        case .middle: return .middleDrag
        case .button4, .button5: return .none
        }
    }
}
