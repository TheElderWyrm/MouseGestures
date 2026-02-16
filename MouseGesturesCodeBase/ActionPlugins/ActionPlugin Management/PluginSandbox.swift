import Cocoa

// MARK: - Plugin Sandbox

/// Provides a sandboxed environment for plugin execution
public class PluginSandbox {
    
    // MARK: - Properties
    
    private let plugin: GestureActionPlugin
    private let sandboxedContext: SandboxedPluginContext
    private let permissions: PluginPermissions
    private let resourceMonitor: PluginResourceMonitor
    private let identifier: String
    
    // MARK: - Initialization
    
    init(plugin: GestureActionPlugin, permissions: PluginPermissions = .default) {
        self.plugin = plugin
        self.identifier = plugin.identifier
        self.permissions = permissions
        self.sandboxedContext = SandboxedPluginContext(pluginId: plugin.identifier, permissions: permissions)
        self.resourceMonitor = PluginResourceMonitor(pluginId: plugin.identifier)
    }
    
    // MARK: - Sandboxed Execution
    
    /// Execute an action within the sandbox
    func executeAction(_ action: PluginAction, with parameters: ActionParameters) throws {
        // Check if plugin has permission for this type of action
        guard permissions.canExecuteAction(action) else {
            throw PluginSandboxError.permissionDenied("Plugin lacks permission to execute action: \(action.id)")
        }
        
        // Start monitoring resources
        resourceMonitor.startMonitoring()
        
        // Set up execution context
        sandboxedContext.beginExecution()
        
        defer {
            // Clean up after execution
            sandboxedContext.endExecution()
            resourceMonitor.stopMonitoring()
            
            // Log resource usage if excessive
            if resourceMonitor.isExcessive() {
                log.log("⚠️ Plugin '\(identifier)' used excessive resources: \(resourceMonitor.summary())")
            }
        }
        
        // Check resource limits
        try resourceMonitor.checkLimits()
        
        // Execute the action with timeout
        let timeout: TimeInterval = permissions.executionTimeout
        let completed = DispatchSemaphore(value: 0)
        var executionError: Error?
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.plugin.execute(action: action, with: parameters, context: self.sandboxedContext)
            } catch {
                executionError = error
            }
            completed.signal()
        }
        
        let result = completed.wait(timeout: .now() + timeout)
        
        if result == .timedOut {
            throw PluginSandboxError.executionTimeout("Action execution timed out after \(timeout) seconds")
        }
        
        if let error = executionError {
            throw error
        }
    }
    
    /// Validate an action within the sandbox
    func validateAction(_ action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        guard permissions.canExecuteAction(action) else {
            return ValidationResult.invalid(error: "Plugin lacks permission for this action")
        }
        
        return plugin.validate(action: action, with: parameters)
    }
    
    // MARK: - Lifecycle Management
    
    func initialize() throws {
        sandboxedContext.beginInitialization()
        defer { sandboxedContext.endInitialization() }
        
        try plugin.initialize(context: sandboxedContext)
    }
    
    func cleanup() {
        plugin.cleanup()
        sandboxedContext.cleanup()
        resourceMonitor.cleanup()
    }
}

// MARK: - Sandboxed Plugin Context

/// A restricted context provided to plugins that limits their access to system resources
class SandboxedPluginContext: PluginContext {
    
    private let pluginId: String
    private let permissions: PluginPermissions
    private var notificationObservers: [NSObjectProtocol] = []
    private var isExecuting = false
    private let accessQueue = DispatchQueue(label: "com.mousegestures.sandbox.context", attributes: .concurrent)
    
    init(pluginId: String, permissions: PluginPermissions) {
        self.pluginId = pluginId
        self.permissions = permissions
    }
    
    // MARK: - Context Protocol Implementation
    
    var configuration: Configuration {
        // Provide read-only access to configuration
        guard permissions.canAccessConfiguration else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to access configuration without permission")
            // Return a mock configuration with minimal data
            return Configuration.shared // Still return shared but log the access attempt
        }
        return Configuration.shared
    }
    
    var logger: PluginLogger {
        // Return a sandboxed logger that prefixes messages with plugin ID
        return SandboxedLogger(pluginId: pluginId)
    }
    
    func observeNotification(name: NSNotification.Name, handler: @escaping (Notification) -> Void) -> NSObjectProtocol {
        // Only allow observing permitted notifications
        guard permissions.canObserveNotification(name) else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to observe restricted notification: \(name)")
            return NSObject() // Return dummy observer
        }
        
        let observer = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Ensure plugin is still valid before calling handler
            self?.accessQueue.sync {
                guard self?.isExecuting ?? false else { return }
                handler(notification)
            }
        }
        
        accessQueue.async(flags: .barrier) { [weak self] in
            self?.notificationObservers.append(observer)
        }
        
        return observer
    }
    
    func postNotification(name: NSNotification.Name, userInfo: [String: Any]?) {
        // Only allow posting permitted notifications
        guard permissions.canPostNotification(name) else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to post restricted notification: \(name)")
            return
        }
        
        // Add plugin ID to userInfo for tracking
        var enrichedUserInfo = userInfo ?? [:]
        enrichedUserInfo["pluginId"] = pluginId
        
        NotificationCenter.default.post(name: name, object: nil, userInfo: enrichedUserInfo)
    }
    
    func preference(for key: String) -> Any? {
        // Only allow access to plugin-specific preferences
        guard permissions.canAccessPreferences else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to access preferences without permission")
            return nil
        }
        
        let sandboxedKey = "\(pluginId).\(key)"
        return UserDefaults.standard.object(forKey: sandboxedKey)
    }
    
    func setPreference(_ value: Any?, for key: String) {
        guard permissions.canModifyPreferences else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to modify preferences without permission")
            return
        }
        
        let sandboxedKey = "\(pluginId).\(key)"
        
        if let value = value {
            UserDefaults.standard.set(value, forKey: sandboxedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: sandboxedKey)
        }
    }
    
    func executeAction(identifier: String, parameters: ActionParameters) throws {
        // Plugins must request permission through PluginManager
        guard permissions.canExecuteOtherActions else {
            throw PluginSandboxError.permissionDenied("Plugin cannot execute other actions directly")
        }
        
        // Route through PluginManager with sender identification
        PluginManager.shared.executeActionFromPlugin(
            identifier: identifier,
            parameters: parameters,
            requestingPlugin: pluginId
        )
    }
    
    func showNotification(title: String, message: String, style: NotificationStyle) {
        guard permissions.canShowNotifications else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to show notification without permission")
            return
        }
        
        // Add plugin attribution to notification
        let attributedTitle = "[\(pluginId)] \(title)"
        
        DispatchQueue.main.async {
            PluginManager.shared.showPluginNotification(
                title: attributedTitle,
                message: message,
                style: style,
                pluginId: self.pluginId
            )
        }
    }
    
    // MARK: - System Services Implementation
    
    func sendKeyboardShortcut(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        guard permissions.canAccessSystemAPIs else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to send keyboard shortcut without permission")
            return
        }
        
        // Release all modifiers first (shared utility from Extensions.swift)
        releaseAllModifierKeys()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
            
            keyDown.flags = modifiers
            keyUp.flags = modifiers
            
            keyDown.post(tap: .cghidEventTap)
            usleep(50000)
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    func executeAppleScript(_ script: String) throws {
        guard permissions.canAccessSystemAPIs else {
            throw PluginSandboxError.permissionDenied("Cannot execute AppleScript without system API permission")
        }
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                throw PluginSandboxError.executionFailed("AppleScript error: \(error)")
            }
        }
    }
    
    func getFrontmostApplication() -> NSRunningApplication? {
        guard permissions.canAccessSystemAPIs else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to get frontmost app without permission")
            return nil
        }
        return NSWorkspace.shared.frontmostApplication
    }
    
    func getRunningApplications() -> [NSRunningApplication] {
        guard permissions.canAccessSystemAPIs else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to get running apps without permission")
            return []
        }
        return NSWorkspace.shared.runningApplications
    }
    
    func terminateApplication(_ app: NSRunningApplication) -> Bool {
        guard permissions.canAccessSystemAPIs else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to terminate app without permission")
            return false
        }
        return app.terminate()
    }
    
    func hideApplication(_ app: NSRunningApplication) -> Bool {
        guard permissions.canAccessSystemAPIs else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to hide app without permission")
            return false
        }
        return app.hide()
    }
    
    func getWindowsForApplication(_ pid: pid_t) -> [AXUIElement] {
        guard permissions.canAccessWindowManager else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to get windows without permission")
            return []
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        
        if result == .success, let windows = windowsValue as? [AXUIElement] {
            return windows
        }
        
        return []
    }
    
    func performAccessibilityAction(_ element: AXUIElement, action: String) -> Bool {
        guard permissions.canAccessWindowManager else {
            log.log("⚠️ Plugin '\(pluginId)' attempted accessibility action without permission")
            return false
        }
        
        let result = AXUIElementPerformAction(element, action as CFString)
        return result == .success
    }
    
    func setAccessibilityAttribute(_ element: AXUIElement, attribute: String, value: CFTypeRef) -> Bool {
        guard permissions.canAccessWindowManager else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to set accessibility attribute without permission")
            return false
        }
        
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        return result == .success
    }
    
    func getAccessibilityAttribute(_ element: AXUIElement, attribute: String) -> CFTypeRef? {
        guard permissions.canAccessWindowManager else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to get accessibility attribute without permission")
            return nil
        }
        
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        
        if result == .success {
            return value
        }
        
        return nil
    }
    
    func getTargetWindow(_ params: [String: Any]) -> (AXUIElement, pid_t)? {
        guard permissions.canAccessWindowManager else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to get target window without permission")
            return nil
        }
        
        // Parse params to create WindowTarget
        var target = WindowTargeting.WindowTarget()
        
        if let targetType = params["targetType"] as? String {
            target.targetType = WindowTargeting.TargetType(rawValue: targetType) ?? .frontmost
        }
        if let bundleId = params["bundleId"] as? String {
            target.applicationBundleId = bundleId
        }
        if let title = params["windowTitle"] as? String {
            target.windowTitle = title
        }
        if let age = params["windowAge"] as? Int {
            target.windowAge = age
        }
        
        return WindowTargeting.getTargetWindow(target)
    }
    
    func getTargetWindows(_ params: [String: Any]) -> [(AXUIElement, pid_t)] {
        guard permissions.canAccessWindowManager else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to get target windows without permission")
            return []
        }
        
        var target = WindowTargeting.WindowTarget()
        if let targetType = params["targetType"] as? String {
            target.targetType = WindowTargeting.TargetType(rawValue: targetType) ?? .frontmost
        }
        if let bundleId = params["bundleId"] as? String {
            target.applicationBundleId = bundleId
        }
        if let title = params["windowTitle"] as? String {
            target.windowTitle = title
        }
        if let titleContains = params["windowTitleContains"] as? String {
            target.windowTitleContains = titleContains
        }
        if let age = params["windowAge"] as? Int {
            target.windowAge = age
        }
        
        return WindowTargeting.getTargetWindows(target)
    }
    
    func getAllVisibleWindows() -> [(window: AXUIElement, pid: pid_t)] {
        guard permissions.canAccessWindowManager else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to get all windows without permission")
            return []
        }
        
        return WindowTargeting.getAllVisibleWindows().map { ($0.window, $0.pid) }
    }
    
    func saveData(_ data: Data, to filename: String) throws {
        guard permissions.canAccessFileSystem else {
            throw PluginSandboxError.permissionDenied("Cannot save data without file system permission")
        }
        
        let url = pluginStorageURL().appendingPathComponent(filename)
        try data.write(to: url)
    }
    
    func loadData(from filename: String) throws -> Data {
        guard permissions.canAccessFileSystem else {
            throw PluginSandboxError.permissionDenied("Cannot load data without file system permission")
        }
        
        let url = pluginStorageURL().appendingPathComponent(filename)
        return try Data(contentsOf: url)
    }
    
    func fileExists(_ filename: String) -> Bool {
        guard permissions.canAccessFileSystem else {
            return false
        }
        
        let url = pluginStorageURL().appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    func deleteFile(_ filename: String) throws {
        guard permissions.canAccessFileSystem else {
            throw PluginSandboxError.permissionDenied("Cannot delete file without file system permission")
        }
        
        let url = pluginStorageURL().appendingPathComponent(filename)
        try FileManager.default.removeItem(at: url)
    }
    
    private func pluginStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let pluginFolder = appSupport
            .appendingPathComponent("MouseGestures")
            .appendingPathComponent("PluginData")
            .appendingPathComponent(pluginId)
        
        try? FileManager.default.createDirectory(at: pluginFolder,
                                                withIntermediateDirectories: true)
        return pluginFolder
    }
    
    func getProfiles() -> [[String: Any]] {
        guard permissions.canAccessConfiguration else {
            return []
        }
        // Return profiles as dictionaries for sandbox isolation
        return Configuration.shared.profiles.map { profile in
            [
                "id": profile.id.uuidString,
                "name": profile.name,
                "isActive": profile.id == Configuration.shared.activeProfileId
            ]
        }
    }
    
    func getActiveProfileId() -> UUID? {
        guard permissions.canAccessConfiguration else {
            return nil
        }
        return Configuration.shared.activeProfileId
    }
    
    func applyProfile(profileId: UUID) {
        guard permissions.canAccessConfiguration else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to apply profile without permission")
            return
        }
        
        // Find and apply the profile, setting it as the new default so it persists
        if let profile = Configuration.shared.profiles.first(where: { $0.id == profileId }) {
            Configuration.shared.applyProfile(profile, setAsDefault: true)
        }
    }
    
    func saveConfiguration() {
        guard permissions.canAccessConfiguration else {
            log.log("⚠️ Plugin '\(pluginId)' attempted to save configuration without permission")
            return
        }
        
        Configuration.shared.save()
    }
    
    // MARK: - Execution State Management
    
    func beginExecution() {
        accessQueue.async(flags: .barrier) { [weak self] in
            self?.isExecuting = true
        }
    }
    
    func endExecution() {
        accessQueue.async(flags: .barrier) { [weak self] in
            self?.isExecuting = false
        }
    }
    
    func beginInitialization() {
        isExecuting = true
    }
    
    func endInitialization() {
        isExecuting = false
    }
    
    func cleanup() {
        accessQueue.async(flags: .barrier) { [weak self] in
            self?.notificationObservers.forEach { observer in
                NotificationCenter.default.removeObserver(observer)
            }
            self?.notificationObservers.removeAll()
            self?.isExecuting = false
        }
    }
}

// MARK: - Plugin Permissions

/// Defines what a plugin is allowed to do
public struct PluginPermissions: Equatable {
    
    // Access permissions
    public var canAccessConfiguration: Bool = false
    public var canAccessPreferences: Bool = true
    public var canModifyPreferences: Bool = true
    public var canShowNotifications: Bool = true
    public var canExecuteOtherActions: Bool = false
    public var canAccessFileSystem: Bool = false
    public var canAccessNetwork: Bool = false
    public var canAccessWindowManager: Bool = false
    public var canAccessSystemAPIs: Bool = false
    
    // Notification permissions
    public var allowedNotificationsToObserve: Set<NSNotification.Name> = []
    public var allowedNotificationsToPost: Set<NSNotification.Name> = []
    
    // Resource limits
    public var maxMemoryUsage: Int = 100_000_000 // 100 MB
    public var maxCPUUsage: Double = 50.0 // 50% of one core
    public var executionTimeout: TimeInterval = 5.0 // 5 seconds
    
    // Action restrictions
    public var allowedActionCategories: Set<ActionCategory> = []
    public var blockedActionIds: Set<String> = []
    
    // MARK: - Presets
    
    /// Default permissions for built-in plugins
    public static let builtIn = PluginPermissions(
        canAccessConfiguration: true,
        canAccessPreferences: true,
        canModifyPreferences: true,
        canShowNotifications: true,
        canExecuteOtherActions: true,
        canAccessFileSystem: true,
        canAccessNetwork: false,
        canAccessWindowManager: true,
        canAccessSystemAPIs: true,
        allowedNotificationsToObserve: [
            .init("GestureConfigurationChanged"),
            .init("ProfileSwitched"),
            .init("ApplicationSwitched")
        ],
        allowedNotificationsToPost: [
            .init("PluginActionCompleted"),
            .init("PluginNotification"),
            .init("GestureConfigurationChanged")
        ],
        maxMemoryUsage: 200_000_000, // 200 MB
        maxCPUUsage: 80.0,
        executionTimeout: 10.0,
        allowedActionCategories: Set(ActionCategory.allCases),
        blockedActionIds: []
    )
    
    /// Default permissions for third-party plugins
    public static let `default` = PluginPermissions(
        canAccessConfiguration: false,
        canAccessPreferences: true,
        canModifyPreferences: true,
        canShowNotifications: true,
        canExecuteOtherActions: false,
        canAccessFileSystem: false,
        canAccessNetwork: false,
        canAccessWindowManager: false,
        canAccessSystemAPIs: false,
        allowedNotificationsToObserve: [
            .init("PluginActionCompleted")
        ],
        allowedNotificationsToPost: [
            .init("PluginNotification")
        ],
        maxMemoryUsage: 50_000_000, // 50 MB
        maxCPUUsage: 25.0,
        executionTimeout: 3.0,
        allowedActionCategories: [],
        blockedActionIds: []
    )
    
    /// Restricted permissions for untrusted plugins
    public static let restricted = PluginPermissions(
        canAccessConfiguration: false,
        canAccessPreferences: false,
        canModifyPreferences: false,
        canShowNotifications: false,
        canExecuteOtherActions: false,
        canAccessFileSystem: false,
        canAccessNetwork: false,
        canAccessWindowManager: false,
        canAccessSystemAPIs: false,
        allowedNotificationsToObserve: [],
        allowedNotificationsToPost: [],
        maxMemoryUsage: 10_000_000, // 10 MB
        maxCPUUsage: 10.0,
        executionTimeout: 1.0,
        allowedActionCategories: [],
        blockedActionIds: []
    )
    
    // MARK: - Permission Checking
    
    func canObserveNotification(_ name: NSNotification.Name) -> Bool {
        return allowedNotificationsToObserve.contains(name) ||
               allowedNotificationsToObserve.isEmpty // Empty set means all allowed
    }
    
    func canPostNotification(_ name: NSNotification.Name) -> Bool {
        return allowedNotificationsToPost.contains(name) ||
               allowedNotificationsToPost.isEmpty // Empty set means all allowed
    }
    
    func canExecuteAction(_ action: PluginAction) -> Bool {
        // Check if action is blocked
        if blockedActionIds.contains(action.id) {
            return false
        }
        
        // Check category permissions if specified
        if !allowedActionCategories.isEmpty {
            // Need to determine action category - this would require additional metadata
            return true // For now, allow if not explicitly blocked
        }
        
        return true
    }
}

// MARK: - Resource Monitoring

/// Monitors resource usage by a plugin
class PluginResourceMonitor {
    
    private let pluginId: String
    private var startTime: Date?
    private var peakMemory: Int = 0
    private var totalCPUTime: TimeInterval = 0
    private var lastCPUCheck: Date?
    private let queue = DispatchQueue(label: "com.mousegestures.resource.monitor")
    
    init(pluginId: String) {
        self.pluginId = pluginId
    }
    
    func startMonitoring() {
        queue.async { [weak self] in
            self?.startTime = Date()
            self?.lastCPUCheck = Date()
            self?.peakMemory = 0
            self?.totalCPUTime = 0
        }
    }
    
    func stopMonitoring() {
        queue.async { [weak self] in
            self?.startTime = nil
            self?.lastCPUCheck = nil
        }
    }
    
    func checkLimits() throws {
        // This is a simplified check - real implementation would need system APIs
        // to accurately measure memory and CPU usage
    }
    
    func isExcessive() -> Bool {
        return queue.sync {
            // Check if resource usage was excessive
            return peakMemory > 100_000_000 || totalCPUTime > 5.0
        }
    }
    
    func summary() -> String {
        return queue.sync {
            return "Memory: \(peakMemory / 1_000_000)MB, CPU Time: \(totalCPUTime)s"
        }
    }
    
    func cleanup() {
        queue.async { [weak self] in
            self?.startTime = nil
            self?.lastCPUCheck = nil
            self?.peakMemory = 0
            self?.totalCPUTime = 0
        }
    }
}

// MARK: - Sandboxed Logger
// Now uses the shared PrefixedLogger from Extensions.swift
typealias SandboxedLogger = PrefixedLogger

// MARK: - Plugin Sandbox Errors

public enum PluginSandboxError: LocalizedError {
    case permissionDenied(String)
    case resourceLimitExceeded(String)
    case executionTimeout(String)
    case invalidOperation(String)
    case sandboxViolation(String)
    case executionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .resourceLimitExceeded(let message):
            return "Resource limit exceeded: \(message)"
        case .executionTimeout(let message):
            return "Execution timeout: \(message)"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        case .sandboxViolation(let message):
            return "Sandbox violation: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}

// MARK: - Plugin Request System

/// Represents a request from a plugin for external functionality
public struct PluginRequest {
    public enum RequestType {
        case executeAction(identifier: String, parameters: ActionParameters)
        case accessFile(path: String, mode: FileAccessMode)
        case openURL(url: URL)
        case accessSystemAPI(api: String)
        case elevatePermissions(permissions: PluginPermissions)
    }
    
    public enum FileAccessMode {
        case read
        case write
        case readWrite
    }
    
    public let pluginId: String
    public let type: RequestType
    public let reason: String?
    public let timestamp: Date
    
    public init(pluginId: String, type: RequestType, reason: String? = nil) {
        self.pluginId = pluginId
        self.type = type
        self.reason = reason
        self.timestamp = Date()
    }
}

// MARK: - Plugin Request Handler

/// Handles requests from sandboxed plugins
public protocol PluginRequestHandler: AnyObject {
    func handleRequest(_ request: PluginRequest, completion: @escaping (Result<Any?, Error>) -> Void)
    func shouldAutoApprove(_ request: PluginRequest) -> Bool
}
