import Foundation
import Cocoa

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
        let currentModifiers = NSEvent.modifierFlags
        return currentModifiers.contains(requiredModifiers)
    }
    
    private func doesScriptReturnTrue() -> Bool {
        guard let script = scriptInfo else { return false }
        
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            
            // Get the script content
            var scriptContent: String?
            if script.isFile, let path = script.scriptPath {
                // Read from file
                do {
                    scriptContent = try String(contentsOfFile: path)
                } catch {
                    log.log("Error reading script file for condition: \(error)")
                    semaphore.signal()
                    return
                }
            } else {
                scriptContent = script.scriptContent
            }
            
            guard let finalScript = scriptContent else {
                log.log("No script content available for condition")
                semaphore.signal()
                return
            }
            
            // Configure process based on script type
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
                process.waitUntilExit()
                
                let exitCode = process.terminationStatus
                
                // Check exit code (0 = true, non-zero = false)
                if exitCode == 0 {
                    // Also check if output contains "true" or "1"
                    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: outputData, encoding: .utf8) {
                        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        result = (trimmed == "true" || trimmed == "1" || trimmed == "yes" || exitCode == 0)
                    } else {
                        result = true // Exit code 0 means success/true
                    }
                } else {
                    result = false
                }
            } catch {
                log.log("Error executing condition script: \(error)")
                result = false
            }
            
            semaphore.signal()
        }
        
        // Wait for script to complete (with timeout)
        _ = semaphore.wait(timeout: .now() + 2.0) // 2 second timeout for condition scripts
        
        return result
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
