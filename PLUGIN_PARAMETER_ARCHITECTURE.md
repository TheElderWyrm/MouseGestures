# Plugin Parameter Architecture

## Current State Analysis

### What Works ✅
- `Gesture.parameters` uses `[String: AnyCodable]` - fully extensible
- `ActionParameters` wrapper provides type-safe accessors
- Plugins define their own `ParameterDefinition` specs
- No hard coupling between gesture storage and parameter types

### The Problem ❌
- `DataStructures.swift` contains hard-coded types (`SearchInfo`, `ScriptInfo`, etc.)
- Creates false impression that plugins need to modify this file
- Blurs the line between "core data structures" and "plugin parameter types"
- Makes system appear less extensible than it actually is

## Recommended Architecture

### Principle: DataStructures.swift is for Core System Types Only

**DataStructures.swift should contain ONLY:**
- Types used by the core gesture system (`GestureTrigger`, `ActivationSettings`, etc.)
- Types used across multiple subsystems (`KeyboardShortcut`, `MouseButtonTrigger`)
- UI-related types that span multiple plugins (`AppTarget`, `WindowLayout`)

**DataStructures.swift should NOT contain:**
- Plugin-specific parameter types
- Action-specific configuration structures

### For Built-in Plugins

**Option 1: Define Types Within Plugin Files (Recommended)**
```swift
// Inside AutomationPlugin.swift
extension AutomationPlugin {
    struct ScriptConfiguration: Codable {
        var scriptType: ScriptType
        var scriptPath: String?
        var scriptContent: String?
        var pythonInterpreter: String?
        
        enum ScriptType: String, Codable {
            case shell, appleScript, python, javascript
        }
    }
}

// Usage in plugin:
func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
    // Decode from ActionParameters
    let config = try parameters.decode(ScriptConfiguration.self, from: "script_config")
    // ... execute with config
}
```

**Option 2: Use Primitives Directly (Simplest)**
```swift
func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
    guard let scriptType = parameters.string(for: "script_type"),
          let scriptContent = parameters.string(for: "script_content") else {
        throw PluginError.invalidParameters("Missing script parameters")
    }
    // ... work directly with primitives
}
```

### For Third-Party Plugins

Plugin developers define their own types:

```swift
// In MyCustomPlugin.swift
class MyCustomPlugin: GestureActionPlugin {
    
    // Define custom parameter types within the plugin
    struct DatabaseConfig: Codable {
        var host: String
        var port: Int
        var database: String
        var username: String
    }
    
    lazy var providedActions: [PluginAction] = [
        PluginAction(
            id: "query_database",
            name: "Query Database",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(key: "host", name: "Host", type: .string, required: true),
                ParameterDefinition(key: "port", name: "Port", type: .number, required: true),
                ParameterDefinition(key: "database", name: "Database", type: .string, required: true),
                ParameterDefinition(key: "username", name: "Username", type: .string, required: true),
                ParameterDefinition(key: "query", name: "SQL Query", type: .string, required: true)
            ]
        )
    ]
    
    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        // Decode custom config from parameters
        let config = DatabaseConfig(
            host: parameters.string(for: "host")!,
            port: Int(parameters.number(for: "port")!),
            database: parameters.string(for: "database")!,
            username: parameters.string(for: "username")!
        )
        
        // Execute with custom type
        executeQuery(config: config, query: parameters.string(for: "query")!)
    }
}
```

## Implementation Strategy

### Phase 1: Add Helper Extensions to ActionParameters

```swift
extension ActionParameters {
    /// Decode a Codable type from a parameter key containing JSON data
    func decode<T: Decodable>(_ type: T.Type, from key: String) throws -> T {
        guard let dict = dictionary(for: key) else {
            throw PluginError.invalidParameters("Missing parameter: \(key)")
        }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(type, from: data)
    }
    
    /// Encode a Codable type to store in parameters
    mutating func encode<T: Encodable>(_ value: T, to key: String) throws {
        let data = try JSONEncoder().encode(value)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        self[key] = AnyCodable(dict)
    }
}
```

### Phase 2: Migration Plan for Built-in Plugins

1. **Move plugin-specific types to plugin files**
   - `ScriptInfo` → `AutomationPlugin.ScriptConfiguration`
   - `SearchInfo` → `CoreActionsPlugin.SearchConfiguration`
   - `WindowSizeParameters` / `WindowPositionParameters` → `WindowManagementPlugin` types

2. **Keep truly shared types in DataStructures.swift**
   - `KeyboardShortcut` (used by gesture system)
   - `MouseButtonTrigger` (used by gesture system)
   - `KeyboardTrigger` (used by gesture system)
   - `AppTarget` (used across multiple plugins)
   - `ApplicationInfo` (shared utility)
   - `FileInfo` (shared utility)
   - `WindowLayout` (shared across system)

3. **Update documentation**
   - Add comments to DataStructures.swift explaining its scope
   - Create plugin development guide showing parameter patterns
   - Document helper methods

### Phase 3: Enhance Plugin System

Add to `PluginProtocol.swift`:

```swift
/// Protocol for plugin-defined parameter types
public protocol PluginParameterType: Codable {
    /// Serialize to ActionParameters dictionary format
    func toParameters() -> [String: AnyCodable]
    
    /// Deserialize from ActionParameters dictionary
    static func from(parameters: ActionParameters) throws -> Self
}

// Provide default implementations
extension PluginParameterType {
    func toParameters() -> [String: AnyCodable] {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict.mapValues { AnyCodable($0) }
    }
    
    static func from(parameters: ActionParameters) throws -> Self {
        let dict = parameters.keys.reduce(into: [String: Any]()) { result, key in
            result[key] = parameters[key]?.value
        }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(Self.self, from: data)
    }
}
```

## Benefits of This Architecture

1. **True Plugin Extensibility**: Plugins can define any parameter structure without modifying core files
2. **Clear Separation**: Core system types vs. plugin-specific types
3. **Type Safety**: Plugins work with strongly-typed structures internally
4. **Flexibility**: System stores everything as `[String: AnyCodable]`
5. **Backward Compatible**: Existing gestures continue working during migration
6. **Better Organization**: Each plugin owns its parameter types

## Documentation for Plugin Developers

**Rule of Thumb:**
- Need a custom data structure? Define it in your plugin file.
- Need to share a type across plugins? Propose it for DataStructures.swift (rare).
- Keep parameters simple? Work directly with ActionParameters accessors.

**Example Plugin Template:**
```swift
class MyPlugin: GestureActionPlugin {
    // 1. Define your parameter types HERE, in your plugin
    struct MyActionConfig: Codable, PluginParameterType {
        var setting1: String
        var setting2: Int
    }
    
    // 2. Describe parameters in PluginAction
    lazy var providedActions: [PluginAction] = [
        PluginAction(
            id: "my_action",
            supportedParameters: [
                ParameterDefinition(key: "setting1", name: "Setting 1", type: .string),
                ParameterDefinition(key: "setting2", name: "Setting 2", type: .number)
            ]
        )
    ]
    
    // 3. Decode when executing
    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        let config = try MyActionConfig.from(parameters: parameters)
        // Work with strongly-typed config
    }
}
```

## Conclusion

The system is already architecturally sound - we just need to:
1. Clarify the scope of DataStructures.swift
2. Provide better helpers for plugins
3. Migrate built-in plugin types out of the core file
4. Document best practices

This makes the plugin system truly extensible without requiring core file modifications.
