import SwiftUI
import Combine

// MARK: - Base UI Plugin

/// Base class for UI plugins providing default implementations
open class BaseUIPlugin: NSObject, UIPlugin, ObservableObject {
    
    // MARK: - Required Properties (Override in subclasses)
    
    open var identifier: String {
        fatalError("Subclass must override identifier")
    }
    
    open var displayName: String {
        fatalError("Subclass must override displayName")
    }
    
    open var iconName: String {
        "questionmark.circle"
    }
    
    open var version: String {
        "1.0.0"
    }
    
    open var author: String {
        "Unknown"
    }
    
    override open var description: String {
        "No description provided"
    }
    
    open var category: UIPluginCategory {
        .custom
    }
    
    // MARK: - Optional Properties
    
    open var minimumAppVersion: String {
        "3.0.0"
    }
    
    open var isVisibleByDefault: Bool {
        true
    }
    
    open var requiredPermissions: UIPluginPermissions {
        .basic
    }
    
    open var sortOrder: Int {
        100
    }
    
    // MARK: - Protected Properties
    
    internal var context: UIPluginContext?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
    }
    
    // MARK: - UIPlugin Protocol
    
    open func initialize(context: UIPluginContext) async throws {
        self.context = context
        
        // Setup any observations
        await setupObservations()
        
        // Perform any async initialization
        try await performInitialization()
    }
    
    @MainActor
    open func createView() -> AnyView {
        AnyView(
            VStack {
                Image(systemName: iconName)
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text(displayName)
                    .font(.title)
                Text("Override createView() in \(String(describing: type(of: self)))")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
    
    @MainActor
    open func createSettingsView() -> AnyView? {
        nil
    }
    
    @MainActor
    open func onActivate() {
        // Override in subclasses if needed
    }
    
    @MainActor
    open func onDeactivate() {
        // Override in subclasses if needed
    }
    
    open func cleanup() {
        cancellables.removeAll()
        context = nil
    }
    
    open func shouldBeVisible(context: UIPluginContext) -> Bool {
        return isVisibleByDefault
    }
    
    // MARK: - Protected Methods for Subclasses
    
    /// Override to setup any observations
    open func setupObservations() async {
        // Override in subclasses
    }
    
    /// Override to perform async initialization
    open func performInitialization() async throws {
        // Override in subclasses
    }
    
    /// Log a message through the plugin context
    internal func log(_ message: String, level: LogLevel = .info) {
        context?.logger("[\(identifier)] \(message)", level: level)
    }
    
    /// Get a preference value
    internal func getPreference<T>(_ key: String, defaultValue: T) -> T {
        return context?.getPreference(key: "\(identifier).\(key)") as? T ?? defaultValue
    }
    
    /// Set a preference value
    internal func setPreference<T>(_ key: String, value: T) {
        context?.setPreference(key: "\(identifier).\(key)", value: value)
    }
    
    /// Post a notification
    internal func postNotification(_ name: Notification.Name, userInfo: [AnyHashable: Any]? = nil) {
        context?.postNotification(name: name, object: self, userInfo: userInfo)
    }
    
    /// Observe a notification
    internal func observeNotification(_ name: Notification.Name, using block: @escaping (Notification) -> Void) {
        guard let context = context else { return }
        
        _ = context.observeNotification(name: name, using: block)
        // Store the observer to prevent it from being deallocated
        NotificationCenter.default.publisher(for: name)
            .sink { notification in
                block(notification)
            }
            .store(in: &cancellables)
    }
    
    /// Show an alert
    @MainActor
    internal func showAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        context?.showAlert(title: title, message: message, style: style)
    }
    
    /// Check if a feature is enabled
    internal func isFeatureEnabled(_ feature: String) -> Bool {
        return context?.isFeatureEnabled(feature) ?? false
    }
}

// MARK: - Standard UI Plugin

/// A standard UI plugin with common functionality
open class StandardUIPlugin: BaseUIPlugin {
    
    // MARK: - Published Properties
    
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var hasUnsavedChanges = false
    
    // MARK: - Override Points
    
    override open func shouldBeVisible(context: UIPluginContext) -> Bool {
        // Can be overridden to add custom visibility logic
        return super.shouldBeVisible(context: context)
    }
    
    // MARK: - Common UI Methods
    
    /// Show a loading indicator
    @MainActor
    internal func showLoading(_ show: Bool) {
        isLoading = show
    }
    
    /// Show an error message
    @MainActor
    internal func showError(_ message: String) {
        errorMessage = message
        showAlert(title: "Error", message: message, style: .critical)
    }
    
    /// Clear error message
    @MainActor
    internal func clearError() {
        errorMessage = nil
    }
    
    /// Mark that there are unsaved changes
    @MainActor
    internal func markAsModified() {
        hasUnsavedChanges = true
    }
    
    /// Mark that changes have been saved
    @MainActor
    internal func markAsSaved() {
        hasUnsavedChanges = false
    }
    
    /// Confirm unsaved changes before proceeding
    @MainActor
    internal func confirmUnsavedChanges() -> Bool {
        guard hasUnsavedChanges else { return true }
        
        let alert = NSAlert()
        alert.messageText = "Unsaved Changes"
        alert.informativeText = "You have unsaved changes. Do you want to discard them?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Developer UI Plugin Base

/// Base class for developer UI plugins with additional features
open class DeveloperUIPluginBase: StandardUIPlugin {
    
    override open var category: UIPluginCategory {
        .developer
    }
    
    override open var requiredPermissions: UIPluginPermissions {
        .full
    }
    
    override open func shouldBeVisible(context: UIPluginContext) -> Bool {
        // Only visible in developer mode
        return context.isDeveloperModeEnabled && super.shouldBeVisible(context: context)
    }
    
    // MARK: - Developer-Specific Methods
    
    /// Log a debug message
    internal func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    /// Log a verbose message
    internal func verbose(_ message: String) {
        log(message, level: .verbose)
    }
    
    /// Measure execution time of a block
    internal func measureTime<T>(_ label: String, block: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        debug("\(label) took \(String(format: "%.3f", elapsed))s")
        return result
    }
    
    /// Measure async execution time
    internal func measureTimeAsync<T>(_ label: String, block: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        debug("\(label) took \(String(format: "%.3f", elapsed))s")
        return result
    }
}
