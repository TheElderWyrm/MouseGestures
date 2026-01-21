import Foundation
import Cocoa

// MARK: - Activation Type

/// Represents a type of activation/trigger condition that a detection plugin can provide
/// Efficiency scores determine which detectors run by default vs. are gated
enum ActivationType: String, CaseIterable, Hashable {
    /// Modifier keys (Cmd, Ctrl, Option, Shift) - event-based, very efficient
    case modifierKey = "modifier_key"
    
    /// Keyboard shortcuts - event-based, efficient
    case keyboardShortcut = "keyboard_shortcut"
    
    /// Mouse button clicks - event-based, efficient
    case mouseButton = "mouse_button"
    
    /// Mouse drag state - event-based, efficient
    case mouseDrag = "mouse_drag"
    
    /// Screen zone detection - requires mouse tracking, less efficient
    case screenZone = "screen_zone"
    
    /// App change detection - event-based, moderate efficiency
    case appChange = "app_change"
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .modifierKey: return "Modifier Keys"
        case .keyboardShortcut: return "Keyboard Shortcuts"
        case .mouseButton: return "Mouse Buttons"
        case .mouseDrag: return "Mouse Drag"
        case .screenZone: return "Screen Zones"
        case .appChange: return "App Change"
        }
    }
    
    /// Efficiency score (higher = more efficient, less resource usage)
    /// 100 = Pure event-based, no polling
    /// 50 = Some computation on events
    /// 0 = Requires active polling/tracking
    var efficiencyScore: Int {
        switch self {
        case .modifierKey: return 100      // Pure event monitoring
        case .keyboardShortcut: return 95  // Event monitoring + lookup
        case .mouseButton: return 90       // Event monitoring + lookup
        case .mouseDrag: return 85         // Event monitoring, some state
        case .appChange: return 70         // Event-based but has computation
        case .screenZone: return 20        // Requires active mouse tracking
        }
    }
    
    /// Whether this activation type should always run (not gated)
    var alwaysActive: Bool {
        return efficiencyScore >= 70
    }
}

// MARK: - Activation State

/// Tracks the current state of an activation type
struct ActivationState {
    let type: ActivationType
    var isEngaged: Bool
    var metadata: [String: Any]
    
    init(type: ActivationType, isEngaged: Bool = false, metadata: [String: Any] = [:]) {
        self.type = type
        self.isEngaged = isEngaged
        self.metadata = metadata
    }
}

// MARK: - Activation Provider Protocol

/// Protocol for plugins that provide activation types
protocol ActivationProvider: AnyObject {
    /// Activation types this plugin provides
    var providedActivationTypes: [ActivationType] { get }
    
    /// Current state for each provided activation type
    func getActivationState(for type: ActivationType) -> ActivationState?
    
    /// Called when the plugin should start/enable detection for a type
    func enableDetection(for type: ActivationType)
    
    /// Called when the plugin should stop/disable detection for a type
    func disableDetection(for type: ActivationType)
    
    /// Whether detection is currently active for a type
    func isDetectionActive(for type: ActivationType) -> Bool
}

// MARK: - Activation Dependency

/// Represents a dependency between activation types
/// "screenZone requires modifierKey" means screen zone detection should only run
/// when modifier key detection reports an engaged state
struct ActivationDependency: Hashable {
    /// The activation type that depends on another
    let dependent: ActivationType
    
    /// The activation type that must be engaged first (the gate)
    let gate: ActivationType
    
    /// Optional: specific condition for the gate (e.g., specific modifiers)
    let condition: String?
    
    init(dependent: ActivationType, gate: ActivationType, condition: String? = nil) {
        self.dependent = dependent
        self.gate = gate
        self.condition = condition
    }
}

// MARK: - Activation Coordinator

/// Coordinates activation states across detection plugins
/// Manages efficiency-based gating so low-efficiency detectors only run when needed
class ActivationCoordinator {
    
    // MARK: - Singleton
    
    static let shared = ActivationCoordinator()
    
    // MARK: - Properties
    
    /// Registered activation providers (weak references)
    private var providers: [ActivationType: Weak<AnyObject>] = [:]
    
    /// Current activation states
    private var activationStates: [ActivationType: ActivationState] = [:]
    
    /// Dependencies computed from gesture configuration
    private var dependencies: Set<ActivationDependency> = []
    
    /// Activation types that are currently enabled
    private var enabledTypes: Set<ActivationType> = []
    
    /// Lock for thread safety (recursive to allow nested calls)
    private let lock = NSRecursiveLock()
    
    // MARK: - Initialization
    
    private init() {
        // Initialize all activation states
        for type in ActivationType.allCases {
            activationStates[type] = ActivationState(type: type)
        }
        
        // Listen for configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationChanged),
            name: NSNotification.Name("GestureConfigurationChanged"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Provider Registration
    
    /// Register a provider for activation types
    func registerProvider(_ provider: ActivationProvider, for types: [ActivationType]) {
        lock.lock()
        defer { lock.unlock() }
        
        for type in types {
            providers[type] = Weak(provider as AnyObject)
        }
        
        log.log("ActivationCoordinator: Registered provider for \(types.map { $0.rawValue })")
    }
    
    /// Unregister a provider
    func unregisterProvider(_ provider: ActivationProvider) {
        lock.lock()
        defer { lock.unlock() }
        
        // Remove all entries for this provider
        providers = providers.filter { _, weakRef in
            guard let obj = weakRef.value else { return false }
            return obj !== (provider as AnyObject)
        }
    }
    
    // MARK: - Activation State Management
    
    /// Called by plugins when an activation type becomes engaged
    func activationEngaged(_ type: ActivationType, metadata: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        
        // Update state
        activationStates[type] = ActivationState(type: type, isEngaged: true, metadata: metadata)
        
        if log.isDebugEnabled {
            log.log("ActivationCoordinator: \(type.displayName) ENGAGED")
        }
        
        // Check if any dependent types should now be enabled
        evaluateGatedActivations()
    }
    
    /// Called by plugins when an activation type is no longer engaged
    func activationDisengaged(_ type: ActivationType) {
        lock.lock()
        defer { lock.unlock() }
        
        // Update state
        activationStates[type] = ActivationState(type: type, isEngaged: false, metadata: [:])
        
        if log.isDebugEnabled {
            log.log("ActivationCoordinator: \(type.displayName) DISENGAGED")
        }
        
        // Check if any dependent types should now be disabled
        evaluateGatedActivations()
    }
    
    /// Get current state for an activation type
    func getState(for type: ActivationType) -> ActivationState {
        lock.lock()
        defer { lock.unlock() }
        return activationStates[type] ?? ActivationState(type: type)
    }
    
    /// Check if an activation type is currently   engaged
    func isEngaged(_ type: ActivationType) -> Bool {
        return getState(for: type).isEngaged
    }
    
    // MARK: - Dependency Management
    
    /// Rebuild dependencies from current gesture configuration
    @objc func configurationChanged() {
        rebuildDependencies()
    }
    
    /// Analyze gestures and build dependency graph
    func rebuildDependencies() {
        lock.lock()
        defer { lock.unlock() }
        
        dependencies.removeAll()
        
        let gestures = Configuration.shared.gestures.filter { $0.isEnabled }
        
        for gesture in gestures {
            // Check what activation types this gesture uses
            let usedTypes = analyzeGestureActivationTypes(gesture)
            
            // If gesture uses multiple types, create dependencies
            // Low-efficiency types depend on high-efficiency types
            let sortedTypes = usedTypes.sorted { $0.efficiencyScore > $1.efficiencyScore }
            
            // Each type depends on all higher-efficiency types in this gesture
            for (index, type) in sortedTypes.enumerated() {
                // Skip always-active types as dependents
                if type.alwaysActive { continue }
                
                // Add dependencies on all higher-efficiency types
                for gateIndex in 0..<index {
                    let gate = sortedTypes[gateIndex]
                    let dependency = ActivationDependency(dependent: type, gate: gate)
                    dependencies.insert(dependency)
                }
            }
        }
        
        if log.isDebugEnabled {
            log.log("ActivationCoordinator: Built \(dependencies.count) dependencies from \(gestures.count) gestures")
            for dep in dependencies {
                log.log("  - \(dep.dependent.displayName) gated by \(dep.gate.displayName)")
            }
        }
        
        // Re-evaluate what should be active
        evaluateGatedActivations()
    }
    
    /// Analyze what activation types a gesture uses
    private func analyzeGestureActivationTypes(_ gesture: Gesture) -> Set<ActivationType> {
        var types = Set<ActivationType>()
        
        // Check for zone-based activation
        if gesture.activation.hasGesture {
            types.insert(.screenZone)
            
            // Screen zones always need modifiers or drag
            if !gesture.modifiers.isEmpty {
                types.insert(.modifierKey)
            }
            
            if gesture.dragModifier != .none {
                types.insert(.mouseDrag)
            }
        }
        
        // Check for keyboard shortcut activation
        if gesture.activation.hasKeyboard && gesture.keyboardTrigger != nil {
            types.insert(.keyboardShortcut)
        }
        
        // Check for mouse button activation
        if gesture.activation.hasMouseButton && gesture.mouseButtonTrigger != nil {
            types.insert(.mouseButton)
        }
        
        return types
    }
    
    // MARK: - Gating Logic
    
    /// Evaluate which gated activation types should be enabled/disabled
    private func evaluateGatedActivations() {
        // Group dependencies by dependent type
        var dependentGates: [ActivationType: Set<ActivationType>] = [:]
        for dep in dependencies {
            dependentGates[dep.dependent, default: []].insert(dep.gate)
        }
        
        // For each potentially gated type
        for type in ActivationType.allCases {
            // Always-active types are always enabled
            if type.alwaysActive {
                enableActivationType(type)
                continue
            }
            
            // Check if all gates for this type are satisfied
            let gates = dependentGates[type] ?? []
            
            if gates.isEmpty {
                // No gates means it depends on nothing - check if any gesture even uses it
                let usedInGestures = dependencies.contains { $0.dependent == type }
                if !usedInGestures {
                    // Not used in any gestures, disable it
                    disableActivationType(type)
                } else {
                    // Used but no gates - keep enabled
                    enableActivationType(type)
                }
            } else {
                // Check if ANY gate is satisfied (OR logic for multiple gates)
                let anyGateSatisfied = gates.contains { isEngaged($0) }
                
                if anyGateSatisfied {
                    enableActivationType(type)
                } else {
                    disableActivationType(type)
                }
            }
        }
    }
    
    /// Enable an activation type
    private func enableActivationType(_ type: ActivationType) {
        guard !enabledTypes.contains(type) else { return }
        
        enabledTypes.insert(type)
        
        if let weakProvider = providers[type], let provider = weakProvider.value as? ActivationProvider {
            if !provider.isDetectionActive(for: type) {
                provider.enableDetection(for: type)
                log.log("ActivationCoordinator: Enabled \(type.displayName)")
            }
        }
    }
    
    /// Disable an activation type
    private func disableActivationType(_ type: ActivationType) {
        guard enabledTypes.contains(type) else { return }
        
        // Don't disable if type is currently engaged (safety check)
        if isEngaged(type) {
            return
        }
        
        enabledTypes.remove(type)
        
        if let weakProvider = providers[type], let provider = weakProvider.value as? ActivationProvider {
            if provider.isDetectionActive(for: type) {
                provider.disableDetection(for: type)
                log.log("ActivationCoordinator: Disabled \(type.displayName)")
            }
        }
    }
    
    // MARK: - Query Methods
    
    /// Get all activation types that should currently be active
    func getActiveActivationTypes() -> Set<ActivationType> {
        lock.lock()
        defer { lock.unlock() }
        return enabledTypes
    }
    
    /// Get all dependencies for a given activation type
    func getDependencies(for type: ActivationType) -> Set<ActivationType> {
        lock.lock()
        defer { lock.unlock() }
        return Set(dependencies.filter { $0.dependent == type }.map { $0.gate })
    }
    
    /// Get all types that depend on a given type
    func getDependents(for type: ActivationType) -> Set<ActivationType> {
        lock.lock()
        defer { lock.unlock() }
        return Set(dependencies.filter { $0.gate == type }.map { $0.dependent })
    }
    
    // MARK: - Debug
    
    /// Get a debug description of the current state
    func debugDescription() -> String {
        lock.lock()
        defer { lock.unlock() }
        
        var desc = "ActivationCoordinator State:\n"
        desc += "Activation States:\n"
        for (type, state) in activationStates.sorted(by: { $0.key.efficiencyScore > $1.key.efficiencyScore }) {
            let engaged = state.isEngaged ? "✓" : "○"
            let active = enabledTypes.contains(type) ? "ACTIVE" : "inactive"
            desc += "  \(engaged) \(type.displayName) (efficiency: \(type.efficiencyScore)) - \(active)\n"
        }
        
        desc += "\nDependencies:\n"
        for dep in dependencies.sorted(by: { $0.dependent.rawValue < $1.dependent.rawValue }) {
            desc += "  \(dep.dependent.displayName) <- \(dep.gate.displayName)\n"
        }
        
        return desc
    }
}

// MARK: - Weak Reference Wrapper

/// Weak reference wrapper for storing providers
private class Weak<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// MARK: - Convenience Extensions

extension ActivationCoordinator {
    
    /// Quick check if screen zone detection should be active
    var shouldTrackMouse: Bool {
        return enabledTypes.contains(.screenZone)
    }
    
    /// Quick check if any modifier is currently held
    var hasActiveModifiers: Bool {
        return isEngaged(.modifierKey)
    }
    
    /// Quick check if any drag is in progress
    var isDragging: Bool {
        return isEngaged(.mouseDrag)
    }
}
