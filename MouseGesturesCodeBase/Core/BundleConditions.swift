import Foundation
import Cocoa

// MARK: - Script Configuration for Conditions

/// Structure to store script info for conditional execution
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

// MARK: - Conditional Logic for Bundle Actions

/// Represents a condition that can be evaluated
struct BundleCondition: Codable, Equatable {
    enum ConditionType: String, Codable, CaseIterable {
        case appIsRunning = "App Is Running"
        case appIsNotRunning = "App Is Not Running"
        case appIsFrontmost = "App Is Frontmost"
        case windowTitleContains = "Window Title Contains"
        case windowTitleEquals = "Window Title Equals"
        case windowExists = "Window Exists"
        case profileIsActive = "Profile Is Active"
        case modifierKeyPressed = "Modifier Key Pressed"
        case scriptReturnsTrue = "Script Returns True"
        case always = "Always True"
        case never = "Never True"
    }

    var type: ConditionType
    var appBundleIdentifier: String? // For app-related conditions
    var appName: String? // Display name for UI
    var windowTitle: String? // For window title conditions
    var profileId: UUID? // For profile conditions
    var profileName: String? // Display name for UI
    var modifierKey: NSEvent.ModifierFlags? // For modifier key conditions
    var scriptInfo: ScriptInfo? // For script conditions
    var negate: Bool = false // If true, inverts the condition result

    init(type: ConditionType,
         appBundleIdentifier: String? = nil,
         appName: String? = nil,
         windowTitle: String? = nil,
         profileId: UUID? = nil,
         profileName: String? = nil,
         modifierKey: NSEvent.ModifierFlags? = nil,
         scriptInfo: ScriptInfo? = nil,
         negate: Bool = false) {
        self.type = type
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.windowTitle = windowTitle
        self.profileId = profileId
        self.profileName = profileName
        self.modifierKey = modifierKey
        self.scriptInfo = scriptInfo
        self.negate = negate
    }

    var displayString: String {
        var result = negate ? "NOT " : ""

        switch type {
        case .appIsRunning:
            result += "If \(appName ?? "App") is running"
        case .appIsNotRunning:
            result += "If \(appName ?? "App") is not running"
        case .appIsFrontmost:
            result += "If \(appName ?? "App") is frontmost"
        case .windowTitleContains:
            result += "If window title contains '\(windowTitle ?? "")'"
        case .windowTitleEquals:
            result += "If window title equals '\(windowTitle ?? "")'"
        case .windowExists:
            result += "If window '\(windowTitle ?? "")' exists"
        case .profileIsActive:
            result += "If profile '\(profileName ?? "")' is active"
        case .modifierKeyPressed:
            result += "If \(modifierKeyDescription) pressed"
        case .scriptReturnsTrue:
            result += "If script '\(scriptInfo?.displayName ?? "")' returns true"
        case .always:
            result += "Always"
        case .never:
            result += "Never"
        }

        return result
    }

    private var modifierKeyDescription: String {
        guard let modifiers = modifierKey else { return "modifier" }
        let s = modifiers.symbolString
        return s.isEmpty ? "No Modifiers" : s
    }

    /// Evaluates the condition and returns true if it passes
    func evaluate() -> Bool {
        let result: Bool

        switch type {
        case .appIsRunning:
            result = isAppRunning()
        case .appIsNotRunning:
            result = !isAppRunning()
        case .appIsFrontmost:
            result = isAppFrontmost()
        case .windowTitleContains:
            result = doesWindowTitleContain()
        case .windowTitleEquals:
            result = doesWindowTitleEqual()
        case .windowExists:
            result = doesWindowExist()
        case .profileIsActive:
            result = isProfileActive()
        case .modifierKeyPressed:
            result = isModifierKeyPressed()
        case .scriptReturnsTrue:
            result = doesScriptReturnTrue()
        case .always:
            result = true
        case .never:
            result = false
        }

        return negate ? !result : result
    }

    private func isAppRunning() -> Bool {
        guard let bundleId = appBundleIdentifier else { return false }
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }

    private func isAppFrontmost() -> Bool {
        guard let bundleId = appBundleIdentifier else { return false }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId
    }

    private func doesWindowTitleContain() -> Bool {
        guard let searchTitle = windowTitle else { return false }

        // Get all windows using accessibility API
        let windows = WindowTargeting.getAllVisibleWindows()

        for window in windows {
            if let title = window.title,
               title.localizedCaseInsensitiveContains(searchTitle) {
                return true
            }
        }
        return false
    }

    private func doesWindowTitleEqual() -> Bool {
        guard let searchTitle = windowTitle else { return false }

        // Get all windows using accessibility API
        let windows = WindowTargeting.getAllVisibleWindows()

        for window in windows {
            if let title = window.title,
               title == searchTitle {
                return true
            }
        }
        return false
    }

    private func doesWindowExist() -> Bool {
        guard let searchTitle = windowTitle else { return false }

        // Get all windows using accessibility API
        let windows = WindowTargeting.getAllVisibleWindows()

        return windows.contains { window in
            if let title = window.title {
                return title.localizedCaseInsensitiveContains(searchTitle)
            }
            return false
        }
    }

    private func isProfileActive() -> Bool {
        guard let profileId = profileId else { return false }
        return Configuration.shared.activeProfile?.id == profileId
    }

    private func isModifierKeyPressed() -> Bool {
        guard let requiredModifiers = modifierKey else { return false }
        // Hardware-only read: a bundle's earlier steps may have already sent
        // a synthetic keyboard shortcut, which would otherwise still be
        // visible in NSEvent.modifierFlags at the moment this condition runs.
        let currentModifiers = NSEvent.ModifierFlags.currentHardware
        return currentModifiers.contains(requiredModifiers)
    }

    private func doesScriptReturnTrue() -> Bool {
        guard let script = scriptInfo else { return false }

        // Resolve the script content (from an external file or inline).
        let scriptContent: String?
        if script.isFile, let path = script.scriptPath {
            do {
                scriptContent = try String(contentsOfFile: path)
            } catch {
                log.log("Error reading script file for condition: \(error)")
                return false
            }
        } else {
            scriptContent = script.scriptContent
        }
        guard let finalScript = scriptContent else {
            log.log("No script content available for condition")
            return false
        }

        // Configure process based on script type
        let process = Process()
        switch script.scriptType {
        case .shellScript:
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", finalScript]

        case .appleScript:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", finalScript]

        case .pythonScript:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", finalScript]

        case .jsScript:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript", "-e", finalScript]
        }

        // Capture output
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Ignore errors for condition evaluation

        do {
            try process.run()
        } catch {
            log.log("Error executing condition script: \(error)")
            return false
        }

        // Bound the condition script to ~2s. The process runs on the calling
        // thread — condition evaluation is only ever reached from
        // BundleActionsPlugin's background execution queue, never the main
        // thread — and a watchdog terminates it if it overruns. The previous
        // semaphore-with-timeout approach, on timeout, both read `result` while
        // the worker thread was still writing it (a data race) AND abandoned a
        // still-running process; terminating bounds the runtime cleanly.
        let timeoutWork = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0, execute: timeoutWork)
        process.waitUntilExit()
        timeoutWork.cancel()

        // Drain stdout so a chatty script can't wedge on a full pipe buffer.
        _ = pipe.fileHandleForReading.readDataToEndOfFile()

        // Exit code 0 == condition passes (unchanged from the prior behavior:
        // the old stdout "true"/"1" test was OR'd with `exitCode == 0`, which
        // made it a no-op — see the honor-output suggestion in the audit).
        return process.terminationStatus == 0
    }
}

/// Represents a logical combination of conditions
struct BundleConditionGroup: Codable, Equatable {
    enum LogicalOperator: String, Codable, CaseIterable {
        case and = "AND"
        case or = "OR"
    }

    var conditions: [BundleCondition]
    var logicalOperator: LogicalOperator

    init(conditions: [BundleCondition] = [], logicalOperator: LogicalOperator = .and) {
        self.conditions = conditions
        self.logicalOperator = logicalOperator
    }

    var displayString: String {
        if conditions.isEmpty {
            return "No conditions"
        }
        if conditions.count == 1 {
            return conditions[0].displayString
        }
        return conditions.map { $0.displayString }.joined(separator: " \(logicalOperator.rawValue) ")
    }

    /// Evaluates all conditions with the specified logical operator
    func evaluate() -> Bool {
        guard !conditions.isEmpty else { return true } // No conditions = always true

        switch logicalOperator {
        case .and:
            // All conditions must be true
            return conditions.allSatisfy { $0.evaluate() }
        case .or:
            // At least one condition must be true
            return conditions.contains { $0.evaluate() }
        }
    }
}

// Extension functionality is now in DataStructures.swift
