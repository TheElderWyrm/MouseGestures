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
}

