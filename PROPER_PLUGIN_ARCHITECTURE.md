# Proper Plugin Architecture - Complete Refactor

## The Problem

The current architecture hard-codes plugin-specific types in core files:

**Current Gesture.swift:**
```swift
struct ActivationSettings {
    var keyboardTrigger: KeyboardTrigger?      // ❌ Detection plugin type
    var mouseButtonTrigger: MouseButtonTrigger? // ❌ Detection plugin type
}

struct Gesture {
    var parameters: [String: AnyCodable]  // ✅ Generic action data
}
```

**The Issue:**
- Core system knows about specific detection methods (keyboard, mouse button)
- Core system knows about specific plugin types
- Adding new detection methods requires modifying core files
- This defeats the entire purpose of a plugin architecture

## The Principle

**NO plugin types should exist in core files. Period.**

This includes:
- Detection plugins (keyboard, mouse button, etc.)
- Action plugins (already handled correctly with generic parameters)
- Even built-in plugins that ship with the app

## Proper Architecture

### What IS Core

**Gesture.swift should ONLY contain:**
```swift
struct GestureTrigger: Codable {
    let zone: ScreenZone           // ✅ System detects zones
    let modifiers: NSEvent.ModifierFlags  // ✅ System detects modifiers  
    let dragModifier: DragModifier  // ✅ System detects drag types
}

struct TimingSettings: Codable {
    var repeatOnHold: Bool
    var repeatInitialDelay: TimeInterval
    var repeatInterval: TimeInterval
    var longPressEnabled: Bool
    var longPressThreshold: TimeInterval
}

struct Gesture: Codable {
    let trigger: GestureTrigger
    var actionIdentifier: String
    var parameters: [String: AnyCodable]  // Action plugin data
    var timing: TimingSettings
    var isEnabled: Bool
    
    // Generic activation data - no typed plugin structs
    var activationMethods: [String]  // Plugin IDs: ["keyboard_detector", "mouse_button_detector"]
    var activationData: [String: AnyCodable]  // Plugin-specific config
    
    var longPressActionIdentifier: String?
    var longPressParameters: [String: AnyCodable]?
}
```

### Detection Plugins Define Their Own Types

**KeyboardShortcutDetectorPlugin.swift:**
```swift
class KeyboardShortcutDetectorPlugin: DetectionPlugin {
    
    // Plugin-specific types defined HERE
    struct KeyboardTrigger: Codable {
        var keyCode: CGKeyCode
        var modifiers: NSEvent.ModifierFlags
        var displayString: String
    }
    
    // Plugin stores/retrieves its own data from generic dictionary
    func configure(with data: [String: AnyCodable]) {
        if let trigger = try? decode(KeyboardTrigger.self, from: data) {
            // Use it
        }
    }
    
    func getConfigurationData() -> [String: AnyCodable] {
        // Encode trigger to generic dict
    }
}
```

**MouseButtonDetectorPlugin.swift:**
```swift
class MouseButtonDetectorPlugin: DetectionPlugin {
    
    struct MouseButtonTrigger: Codable {
        enum MouseButton: String, Codable {
            case left, right, middle, button4, button5
        }
        var button: MouseButton
        var modifiers: NSEvent.ModifierFlags
    }
    
    // Plugin owns its types
}
```

### How Gestures Store Detection Config

```swift
// User configures: "Activate with Cmd+T OR Middle Mouse Button"

let gesture = Gesture(
    trigger: GestureTrigger(zone: .topRight, modifiers: []),
    actionIdentifier: "close_window",
    parameters: [:],
    timing: TimingSettings(),
    isEnabled: true,
    activationMethods: ["keyboard_detector", "mouse_button_detector"],
    activationData: [
        "keyboard_detector": AnyCodable([
            "keyCode": 17,  // T
            "modifiers": 1048576,  // Cmd
            "displayString": "⌘T"
        ]),
        "mouse_button_detector": AnyCodable([
            "button": "middle",
            "modifiers": 0
        ])
    ]
)
```

### UI Dynamically Adapts

**GestureConfigurationSheet.swift:**
```swift
// UI doesn't know about specific detection methods
// It queries the detection plugin manager

struct GestureConfigurationSheet: View {
    @State var availableDetectionMethods: [DetectionPluginInfo] = []
    
    var body: some View {
        ForEach(availableDetectionMethods) { method in
            Toggle(method.name, isOn: binding(for: method))
            
            if isEnabled(method) {
                // Ask plugin for its config UI
                method.plugin.configurationView(
                    data: gesture.activationData[method.id],
                    onChange: { newData in
                        gesture.activationData[method.id] = newData
                    }
                )
            }
        }
    }
}
```

## Migration Strategy

This is a MAJOR refactor. Here's the approach:

### Phase 1: Add Generic Storage (Non-Breaking)

Add new fields to `Gesture` while keeping old ones:
```swift
struct Gesture {
    // OLD (deprecated but still works)
    var activation: ActivationSettings
    
    // NEW (generic)
    var activationMethods: [String]?
    var activationData: [String: AnyCodable]?
}
```

### Phase 2: Detection Plugins Own Their Types

Move types into plugin files:
1. Move `KeyboardTrigger` → `KeyboardShortcutDetectorPlugin.swift`
2. Move `MouseButtonTrigger` → `MouseButtonDetectorPlugin.swift`
3. Add migration helpers to convert old → new format

### Phase 3: Update Detection System

DetectionPluginManager handles generic activation:
```swift
protocol DetectionPlugin {
    // Plugin provides its config data format
    func configurationSchema() -> [ParameterDefinition]
    
    // Plugin provides UI for configuration
    func configurationView(data: [String: AnyCodable]?, onChange: @escaping ([String: AnyCodable]) -> Void) -> NSView
    
    // Plugin checks if gesture matches with its config
    func matches(gesture: Gesture, with data: [String: AnyCodable]) -> Bool
}
```

### Phase 4: Update UI

UI works generically:
- Query available detection plugins
- Show each plugin's configuration UI
- Store results in `activationData`

### Phase 5: Migrate Saved Data

- Read old gestures with typed `ActivationSettings`
- Convert to new generic format
- Save in new format
- Delete old fields

### Phase 6: Delete DataStructures.swift

All types moved to plugins, file is empty, delete it.

### Phase 7: Delete Old Code

Remove deprecated `ActivationSettings` and typed trigger fields.

## Alternative: Minimal Change Approach

If full refactor is too much right now, here's the minimal change:

1. **Move ALL types from DataStructures.swift into respective plugin files**
   - Even if core system imports them
   - At least they live with their owners

2. **Add comments everywhere:**
   ```swift
   // TODO: This creates a compile-time dependency on a plugin type.
   // Should be refactored to use generic [String: AnyCodable] storage.
   var keyboardTrigger: KeyboardShortcutDetectorPlugin.KeyboardTrigger?
   ```

3. **Delete DataStructures.swift**

4. **Document the debt** so future refactoring can address it properly

## Recommendation

I recommend the **Minimal Change Approach** now, with the full refactor planned for later:

1. Move all types into plugin files TODAY
2. Delete DataStructures.swift TODAY  
3. Document the architectural debt
4. Plan the proper refactor as a separate effort

This immediately solves the "modifying core files" problem while acknowledging the deeper architectural issue.

What do you want to do?
