import Foundation

// Enum for drag modifiers (mouse button states)
enum DragModifier: String, Codable, CaseIterable {
    case none = "None"
    case anyDrag = "Any Drag"
    case leftDrag = "Left Drag"
    case rightDrag = "Right Drag"
    case middleDrag = "Middle Drag"

    var displayName: String {
        switch self {
        case .none:      return ""
        case .anyDrag:   return "Any Drag"
        case .leftDrag:  return "Left Drag"
        case .rightDrag: return "Right Drag"
        case .middleDrag: return "Middle Drag"
        }
    }

    // MARK: - MouseButton Conversion

    var correspondingMouseButton: MouseButtonTrigger.MouseButton? {
        switch self {
        case .none, .anyDrag: return nil
        case .leftDrag:  return .left
        case .rightDrag: return .right
        case .middleDrag: return .middle
        }
    }

    static func from(mouseButton: MouseButtonTrigger.MouseButton) -> DragModifier {
        switch mouseButton {
        case .none, .any: return .none
        case .left: return .leftDrag
        case .right: return .rightDrag
        case .middle: return .middleDrag
        case .button4, .button5: return .none
        }
    }
}
