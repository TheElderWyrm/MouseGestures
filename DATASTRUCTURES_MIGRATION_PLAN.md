# DataStructures.swift Migration Plan

## Current Analysis

### Types in DataStructures.swift and Their Usage:

1. **KeyboardShortcut** - UI utility for capturing shortcuts
   - Used by: `KeyboardShortcutField.swift`
   - MOVE TO: `KeyboardShortcutField.swift` (co-locate with usage)

2. **KeyboardTrigger** - Core gesture system type
   - Used by: `Gesture.swift`, detection plugins, UI configuration
   - MOVE TO: `Gesture.swift` (core gesture infrastructure)

3. **MouseButtonTrigger** - Core gesture system type
   - Used by: `Gesture.swift`, detection plugins, UI configuration  
   - MOVE TO: `Gesture.swift` (core gesture infrastructure)

4. **BundledAction** - Plugin-specific type
   - Used by: `BundleActionsPlugin.swift`, `BundleEditorView.swift`
   - MOVE TO: `BundleActionsPlugin.swift` (plugin owns its types)

5. **WindowLayout, WindowSizeParameters, WindowPositionParameters** - Plugin-specific types
   - Used by: `WindowManagementPlugin.swift`
   - MOVE TO: `WindowManagementPlugin.swift` (plugin owns its types)

6. **ApplicationInfo** - NOT USED (false alarm - other methods use similar names)
   - DELETE

7. **FileInfo** - NOT USED
   - DELETE

8. **SearchInfo** - NOT USED
   - DELETE

9. **ScriptInfo** - Used by multiple systems
   - Used by: `BundleConditions.swift` (Core), `AutomationPlugin.swift`
   - PROBLEM: Core system depends on plugin-specific type
   - SOLUTION: Create lightweight `ScriptConfiguration` struct in `BundleConditions.swift`
   - Plugin can use its own richer version internally

10. **AppTarget** - NOT USED (checked - no actual usage found)
    - DELETE

## Migration Steps

### Step 1: Move Core Gesture Types to Gesture.swift
- Move `KeyboardTrigger` → `Gesture.swift`
- Move `MouseButtonTrigger` → `Gesture.swift`
- These are fundamental to the gesture system

### Step 2: Move UI Type to UI File  
- Move `KeyboardShortcut` → `KeyboardShortcutField.swift`
- This is a UI utility, not a core type

### Step 3: Move Plugin Types to Respective Plugins
- Move `BundledAction` → `BundleActionsPlugin.swift`
- Move `WindowLayout`, `WindowSizeParameters`, `WindowPositionParameters` → `WindowManagementPlugin.swift`

### Step 4: Fix ScriptInfo Dependency
Create lightweight version in `BundleConditions.swift`:
```swift
// In BundleConditions.swift
struct ScriptConfiguration: Codable, Equatable {
    enum ScriptType: String, Codable {
        case shellScript = "Shell Script"
        case appleScript = "AppleScript"
        case pythonScript = "Python Script"
        case jsScript = "JavaScript"
    }
    
    var scriptType: ScriptType
    var scriptPath: String?
    var scriptContent: String?
    var isFile: Bool
    var displayName: String
    
    // No pythonInterpreter - use default /usr/bin/python3
}
```

`AutomationPlugin` can define its own richer version internally.

### Step 5: Delete Unused Types
- Delete `ApplicationInfo` (not used)
- Delete `FileInfo` (not used)
- Delete `SearchInfo` (not used)
- Delete `AppTarget` (not used)

### Step 6: Delete DataStructures.swift
Once all types are migrated, delete the file entirely.

### Step 7: Update Imports
- Remove any imports of DataStructures
- Files will automatically see types defined in same file or module

### Step 8: Test Compilation
- Build project and fix any remaining references
- Run tests to ensure nothing broke

## Benefits

1. **True Plugin Architecture**: Plugins own their data structures
2. **Clear Dependencies**: No hidden coupling through shared data file
3. **Easier Maintenance**: Types live with their usage
4. **Better Discoverability**: Developers see types defined where used
5. **Prevents False Dependencies**: New plugin developers won't think they need to modify core files

## Implementation Order

1. Create helper extension for ActionParameters (for future plugin development)
2. Move types to their new homes
3. Fix ScriptInfo dependency in BundleConditions
4. Delete unused types
5. Delete DataStructures.swift
6. Test and verify
7. Commit changes

## Notes for Plugin Developers

After migration, the pattern is:
- Define your parameter types INSIDE your plugin file
- Serialize to/from ActionParameters
- No need to modify core files
- Use `PluginParameterType` protocol for helpers (future enhancement)

Example:
```swift
// MyCustomPlugin.swift
class MyCustomPlugin: GestureActionPlugin {
    struct MyActionConfig: Codable {
        var setting1: String
        var setting2: Int
    }
    
    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        // Decode from parameters
        let config = try decodeConfig(from: parameters)
    }
    
    private func decodeConfig(from params: ActionParameters) throws -> MyActionConfig {
        // Implementation
    }
}
```
