import Foundation
import Cocoa
import Carbon

// Structure to store keyboard shortcut info
struct KeyboardShortcut: Codable, Equatable {
    var keyCode: CGKeyCode
    var modifiers: CGEventFlags
    var displayString: String // For display in UI

    init(keyCode: CGKeyCode, modifiers: CGEventFlags, displayString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
    }
}


// Structure to store application info
struct ApplicationInfo: Codable, Equatable {
    var applicationPath: String? // Full path to .app bundle
    var bundleIdentifier: String? // Bundle identifier (e.g., com.apple.Safari)
    var displayName: String // For display in UI

    init(applicationPath: String? = nil, bundleIdentifier: String? = nil, displayName: String) {
        self.applicationPath = applicationPath
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}


// Structure to store file info
struct FileInfo: Codable, Equatable {
    var filePath: String // Full path to the file
    var displayName: String // For display in UI
    var openWithDefaultApp: Bool // Whether to open with default app or let user choose

    init(filePath: String, displayName: String, openWithDefaultApp: Bool = true) {
        self.filePath = filePath
        self.displayName = displayName
        self.openWithDefaultApp = openWithDefaultApp
    }
}


// Structure to store search info
struct SearchInfo: Codable, Equatable {
    var searchQuery: String // The search query to perform
    var searchScope: SearchScope // Where to search
    var displayName: String // For display in UI

    enum SearchScope: String, Codable, CaseIterable {
        case currentFolder = "Current Folder"
        case homeFolder = "Home Folder"
        case entireMac = "Entire Mac"
        case customPath = "Custom Path"
    }

    var customPath: String? // Only used when searchScope is .customPath

    init(searchQuery: String, searchScope: SearchScope = .entireMac, displayName: String, customPath: String? = nil) {
        self.searchQuery = searchQuery
        self.searchScope = searchScope
        self.displayName = displayName
        self.customPath = customPath
    }
}

// Structure to store script info
struct ScriptInfo: Codable, Equatable {
    enum ScriptType: String, Codable, CaseIterable {
        case shellScript = "Shell Script (sh/bash/zsh)"
        case appleScript = "AppleScript"
        case pythonScript = "Python Script"
        case jsScript = "JavaScript for Automation"
    }

    var scriptType: ScriptType
    var scriptPath: String? // Path to external script file
    var scriptContent: String? // Inline script content
    var isFile: Bool // true if using external file, false if inline
    var displayName: String // For display in UI
    var pythonInterpreter: String? // Path to Python interpreter (for Python scripts)

    init(scriptType: ScriptType, scriptPath: String? = nil, scriptContent: String? = nil, isFile: Bool, displayName: String, pythonInterpreter: String? = nil) {
        self.scriptType = scriptType
        self.scriptPath = scriptPath
        self.scriptContent = scriptContent
        self.isFile = isFile
        self.displayName = displayName
        self.pythonInterpreter = pythonInterpreter ?? "/usr/bin/python3" // Default to python3
    }
}


// Structure for app targeting
struct AppTarget: Codable, Equatable {
    enum TargetType: String, Codable, CaseIterable {
        case frontmost = "Frontmost Application"
        case specificApp = "Specific Application"
        case allAppsExceptFinder = "All Apps Except Finder"
    }

    var targetType: TargetType
    var bundleIdentifier: String? // For specificApp
    var appName: String? // Display name for UI

    init(targetType: TargetType = .frontmost, bundleIdentifier: String? = nil, appName: String? = nil) {
        self.targetType = targetType
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
    }

    var displayString: String {
        switch targetType {
        case .frontmost:
            return "Frontmost Application"
        case .specificApp:
            return appName ?? bundleIdentifier ?? "Specific Application"
        case .allAppsExceptFinder:
            return "All Apps Except Finder"
        }
    }
}

// Structure to store bundled actions for sequential execution
struct BundledAction: Codable, Equatable {
    var id: UUID = UUID()
    var actionIdentifier: String
    var parameters: [String: AnyCodable]
    var delayAfter: TimeInterval?
    var conditionData: Data?

    init(actionIdentifier: String, parameters: [String: AnyCodable] = [:], delayAfter: TimeInterval? = 0.2, conditionData: Data? = nil) {
        self.actionIdentifier = actionIdentifier
        self.parameters = parameters
        self.delayAfter = delayAfter
        self.conditionData = conditionData
    }

    // Computed property for easier condition access
    var condition: BundleConditionGroup? {
        get {
            guard let data = conditionData else { return nil }
            return try? JSONDecoder().decode(BundleConditionGroup.self, from: data)
        }
        set {
            if let newValue = newValue {
                conditionData = try? JSONEncoder().encode(newValue)
            } else {
                conditionData = nil
            }
        }
    }

    // Check if this action should execute based on its condition
    func shouldExecute() -> Bool {
        guard let condition = condition else { return true } // No condition = always execute
        return condition.evaluate()
    }

    var displayName: String {
        var name: String
        if let (_, action) = PluginManager.shared.getAction(identifier: actionIdentifier) {
            name = action.name
        } else {
            name = actionIdentifier
        }

        // Add condition indicator if present
        if let condition = condition, !condition.conditions.isEmpty {
            name = "[IF] " + name
        }

        return name
    }
}

// Structure for window layouts
struct WindowLayout: Codable, Equatable {
    struct WindowInfo: Codable, Equatable {
        var appBundleIdentifier: String
        var appName: String
        var windowTitle: String?
        var position: CGPoint
        var size: CGSize
        var isMinimized: Bool
        var spaceNumber: Int?
    }

    var name: String
    var windows: [WindowInfo]
    var dateCreated: Date

    init(name: String, windows: [WindowInfo] = []) {
        self.name = name
        self.windows = windows
        self.dateCreated = Date()
    }
}

// Structure for window size parameters
struct WindowSizeParameters: Codable, Equatable {
    var width: Int?
    var height: Int?
    var widthPercent: Int?  // Percentage of screen width
    var heightPercent: Int? // Percentage of screen height
    var maintainAspectRatio: Bool

    init(width: Int? = nil, height: Int? = nil, widthPercent: Int? = nil, heightPercent: Int? = nil, maintainAspectRatio: Bool = false) {
        self.width = width
        self.height = height
        self.widthPercent = widthPercent
        self.heightPercent = heightPercent
        self.maintainAspectRatio = maintainAspectRatio
    }

    var displayString: String {
        var parts: [String] = []
        if let w = width { parts.append("W: \(w)px") }
        if let h = height { parts.append("H: \(h)px") }
        if let wp = widthPercent { parts.append("W: \(wp)%") }
        if let hp = heightPercent { parts.append("H: \(hp)%") }
        if maintainAspectRatio { parts.append("(Keep Ratio)") }
        return parts.joined(separator: ", ")
    }
}

// Structure for window position parameters
struct WindowPositionParameters: Codable, Equatable {
    enum PositionType: String, Codable, CaseIterable {
        case absolute = "Absolute Position"
        case relative = "Relative to Current"
        case screenPercentage = "Screen Percentage"
        case preset = "Preset Position"
    }

    enum PresetPosition: String, Codable, CaseIterable {
        case topLeft = "Top Left"
        case topCenter = "Top Center"
        case topRight = "Top Right"
        case middleLeft = "Middle Left"
        case center = "Center"
        case middleRight = "Middle Right"
        case bottomLeft = "Bottom Left"
        case bottomCenter = "Bottom Center"
        case bottomRight = "Bottom Right"
    }

    var positionType: PositionType
    var x: Int?
    var y: Int?
    var xPercent: Int? // Percentage of screen width
    var yPercent: Int? // Percentage of screen height
    var preset: PresetPosition?

    init(positionType: PositionType = .absolute, x: Int? = nil, y: Int? = nil, xPercent: Int? = nil, yPercent: Int? = nil, preset: PresetPosition? = nil) {
        self.positionType = positionType
        self.x = x
        self.y = y
        self.xPercent = xPercent
        self.yPercent = yPercent
        self.preset = preset
    }

    var displayString: String {
        switch positionType {
        case .absolute:
            return "X: \(x ?? 0), Y: \(y ?? 0)"
        case .relative:
            let xStr = x ?? 0 > 0 ? "+\(x ?? 0)" : "\(x ?? 0)"
            let yStr = y ?? 0 > 0 ? "+\(y ?? 0)" : "\(y ?? 0)"
            return "X: \(xStr), Y: \(yStr)"
        case .screenPercentage:
            return "X: \(xPercent ?? 0)%, Y: \(yPercent ?? 0)%"
        case .preset:
            return preset?.rawValue ?? "Unknown"
        }
    }
}

// Structure for mouse button trigger (modifier + mouse button)
struct MouseButtonTrigger: Codable, Equatable {
    enum MouseButton: String, Codable, CaseIterable {
        case left = "Left Click"
        case right = "Right Click"
        case middle = "Middle Click"
        case button4 = "Button 4"
        case button5 = "Button 5"
    }

    var button: MouseButton
    var modifiers: NSEvent.ModifierFlags
    var displayString: String // For display in UI (e.g., "⌘+Left Click")

    init(button: MouseButton, modifiers: NSEvent.ModifierFlags) {
        self.button = button
        self.modifiers = modifiers
        self.displayString = MouseButtonTrigger.createDisplayString(button: button, modifiers: modifiers)
    }

    static func createDisplayString(button: MouseButton, modifiers: NSEvent.ModifierFlags) -> String {
        let modStr = modifiers.symbolString
        return modStr.isEmpty ? button.rawValue : "\(modStr)+\(button.rawValue)"
    }
}

struct KeyboardTrigger: Codable, Equatable {
    var keyCode: CGKeyCode
    var modifiers: NSEvent.ModifierFlags
    var displayString: String // For display in UI (e.g., "⌘⇧T")

    init(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags, displayString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
    }

    // Helper to create display string from key code and modifiers
    static func createDisplayString(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> String {
        let modStr = modifiers.symbolString
        return "\(modStr)\(keyCode.displayString)"
    }
}
