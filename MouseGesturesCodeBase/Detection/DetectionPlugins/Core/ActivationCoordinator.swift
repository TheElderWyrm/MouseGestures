import Foundation
import Cocoa

// MARK: - Activation Type

/// Represents a type of activation/trigger condition that a detection plugin can provide.
/// This enum defines identity and display names only. All behavioral properties
/// (efficiency, gating, infrastructure) are declared by the plugins themselves
/// through the ActivationProvider protocol, keeping the coordinator plugin-agnostic.
enum ActivationType: String, CaseIterable, Hashable {
    case modifierKey = "modifier_key"
    case keyboardShortcut = "keyboard_shortcut"
    case mouseButton = "mouse_button"
    case screenZone = "screen_zone"
    case appChange = "app_change"
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .modifierKey: return "Modifier Keys"
        case .keyboardShortcut: return "Keyboard Shortcuts"
        case .mouseButton: return "Mouse Buttons"
        case .screenZone: return "Screen Zones"
        case .appChange: return "App Change"
        }
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

/// Protocol for plugins that provide activation types.
/// Plugins declare all behavioral properties — the coordinator never inspects
/// plugin-specific details like modifier flags or gesture fields directly.
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
    
    // MARK: - Plugin-Declared Behavioral Properties
    
    /// Efficiency score for an activation type (higher = more efficient, less resource usage)
    /// 100 = Pure event-based, no polling. 0 = Requires active polling/tracking.
    func efficiencyScore(for type: ActivationType) -> Int
    
    /// Whether this type should always run when used by gestures (not gated by other types)
    func isAlwaysActive(for type: ActivationType) -> Bool
    
    /// Whether this type provides infrastructure (runs unconditionally, e.g. app detection)
    func isInfrastructure(for type: ActivationType) -> Bool
    
    /// Whether a gesture uses this plugin's activation type.
    /// This is the single source of truth — it should match the same logic the plugin
    /// uses when actually detecting/triggering gestures (unifying the activation map).
    func gestureUsesActivation(_ gesture: Gesture, for type: ActivationType) -> Bool
    
    /// Validate whether the current gate state justifies enabling a dependent type.
    /// Called when this provider's activation type is a gate for a dependent type.
    /// `dependentType`: the type that wants to be enabled
    /// `gestures`: enabled gestures that use the dependent type
    /// Returns true if the current engaged state actually warrants enabling the dependent.
    ///
    /// Default implementation: returns true if engaged (simple gate check).
    /// Plugins can override for precision gating (e.g., checking if held modifiers
    /// match any gesture that actually needs the dependent type).
    func validateGate(for dependentType: ActivationType, gestures: [Gesture]) -> Bool
}

// MARK: - Default Implementations

extension ActivationProvider {
    func efficiencyScore(for type: ActivationType) -> Int { return 50 }
    func isAlwaysActive(for type: ActivationType) -> Bool { return efficiencyScore(for: type) >= 70 }
    func isInfrastructure(for type: ActivationType) -> Bool { return false }
    
    func validateGate(for dependentType: ActivationType, gestures: [Gesture]) -> Bool {
        // Default: gate is satisfied if this provider is engaged
        // (The coordinator checks engagement before calling this)
        return true
    }
}

// MARK: - Activation Dependency

/// Represents a dependency between activation types
struct ActivationDependency: Hashable {
    let dependent: ActivationType
    let gate: ActivationType
    let condition: String?
    
    init(dependent: ActivationType, gate: ActivationType, condition: String? = nil) {
        self.dependent = dependent
        self.gate = gate
        self.condition = condition
    }
}

// MARK: - Activation Coordinator

/// Coordinates activation states across detection plugins.
/// This class is entirely plugin-agnostic — it queries registered providers for all
/// behavioral decisions rather than containing plugin-specific logic.
class ActivationCoordinator {
    
    // MARK: - Singleton
    
    static let shared = ActivationCoordinator()
    
    // MARK: - Properties
    
    /// Registered activation providers (weak references)
    private var providers: [ActivationType: Weak<AnyObject>] = [:]
    
    /// Current activation states
    private var activationStates: [ActivationType: ActivationState] = [:]
    
    /// Dependencies computed from gesture configuration (kept for debug/query)
    private var dependencies: Set<ActivationDependency> = []
    
    /// Per-gesture gate groups for each dependent type.
    /// Each entry is a list of gate sets — one set per gesture that uses the dependent type.
    /// A dependent should be enabled if ANY gate group has ALL its gates satisfied.
    /// This ensures that a gesture requiring both modifiers + mouse button won't
    /// enable screen zones when only the mouse button is held.
    private var gateGroups: [ActivationType: [Set<ActivationType>]] = [:]
    
    /// Activation types that are currently enabled
    private var enabledTypes: Set<ActivationType> = []
    
    /// Cached per-type gesture lists: which enabled gestures use each activation type.
    /// Rebuilt together with dependencies for efficient gate validation lookups.
    private var gesturesPerType: [ActivationType: [Gesture]] = [:]
    
    /// Lock for thread safety (recursive to allow nested calls)
    private let lock = NSRecursiveLock()
    
    // MARK: - Initialization
    
    private init() {
        for type in ActivationType.allCases {
            activationStates[type] = ActivationState(type: type)
        }
        
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
    
    func registerProvider(_ provider: ActivationProvider, for types: [ActivationType]) {
        lock.lock()
        defer { lock.unlock() }
        
        for type in types {
            providers[type] = Weak(provider as AnyObject)
        }
        
        log.log("ActivationCoordinator: Registered provider for \(types.map { $0.rawValue })")
    }
    
    func unregisterProvider(_ provider: ActivationProvider) {
        lock.lock()
        defer { lock.unlock() }
        
        providers = providers.filter { _, weakRef in
            guard let obj = weakRef.value else { return false }
            return obj !== (provider as AnyObject)
        }
    }
    
    func pluginStopping(_ provider: ActivationProvider) {
        lock.lock()
        defer { lock.unlock() }
        
        for type in provider.providedActivationTypes {
            if activationStates[type]?.isEngaged == true {
                activationStates[type] = ActivationState(type: type, isEngaged: false, metadata: [:])
            }
            enabledTypes.remove(type)
        }
        
        log.log("ActivationCoordinator: Plugin stopping - cleaned up \(provider.providedActivationTypes.map { $0.displayName })")
    }
    
    // MARK: - Activation State Management
    
    func activationEngaged(_ type: ActivationType, metadata: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        
        activationStates[type] = ActivationState(type: type, isEngaged: true, metadata: metadata)
        
        if log.isDebugEnabled {
            log.log("ActivationCoordinator: \(type.displayName) ENGAGED")
        }
        
        evaluateGatedActivations()
    }
    
    func activationDisengaged(_ type: ActivationType) {
        lock.lock()
        defer { lock.unlock() }
        
        activationStates[type] = ActivationState(type: type, isEngaged: false, metadata: [:])
        
        if log.isDebugEnabled {
            log.log("ActivationCoordinator: \(type.displayName) DISENGAGED")
        }
        
        evaluateGatedActivations()
    }
    
    func getState(for type: ActivationType) -> ActivationState {
        lock.lock()
        defer { lock.unlock() }
        return activationStates[type] ?? ActivationState(type: type)
    }
    
    func isEngaged(_ type: ActivationType) -> Bool {
        return getState(for: type).isEngaged
    }
    
    // MARK: - Provider Query Helpers
    
    /// Get the provider for an activation type (if registered and alive)
    private func getProvider(for type: ActivationType) -> ActivationProvider? {
        guard let weakRef = providers[type], let obj = weakRef.value else { return nil }
        return obj as? ActivationProvider
    }
    
    /// Query provider for efficiency score, with fallback
    private func queryEfficiencyScore(for type: ActivationType) -> Int {
        return getProvider(for: type)?.efficiencyScore(for: type) ?? 50
    }
    
    /// Query provider for always-active status
    private func queryIsAlwaysActive(for type: ActivationType) -> Bool {
        return getProvider(for: type)?.isAlwaysActive(for: type) ?? false
    }
    
    /// Query provider for infrastructure status
    private func queryIsInfrastructure(for type: ActivationType) -> Bool {
        return getProvider(for: type)?.isInfrastructure(for: type) ?? false
    }
    
    /// Ask providers which activation types a gesture uses
    private func queryActivationTypes(for gesture: Gesture) -> Set<ActivationType> {
        var types = Set<ActivationType>()
        for (type, weakRef) in providers {
            guard let obj = weakRef.value, let provider = obj as? ActivationProvider else { continue }
            if provider.gestureUsesActivation(gesture, for: type) {
                types.insert(type)
            }
        }
        return types
    }
    
    // MARK: - Dependency Management
    
    @objc func configurationChanged() {
        rebuildDependencies()
    }
    
    func rebuildDependencies() {
        lock.lock()
        defer { lock.unlock() }
        
        dependencies.removeAll()
        gateGroups.removeAll()
        gesturesPerType.removeAll()
        
        let gestures = Configuration.shared.gestures.filter { $0.isEnabled }
        
        for gesture in gestures {
            let usedTypes = queryActivationTypes(for: gesture)
            
            // Cache which gestures use each type
            for type in usedTypes {
                gesturesPerType[type, default: []].append(gesture)
            }
            
            // Build dependencies: low-efficiency types depend on high-efficiency types
            let sortedTypes = usedTypes.sorted { queryEfficiencyScore(for: $0) > queryEfficiencyScore(for: $1) }
            
            for (index, type) in sortedTypes.enumerated() {
                if queryIsAlwaysActive(for: type) { continue }
                
                // Collect ALL gates for this dependent type from THIS gesture
                var gatesForThisGesture = Set<ActivationType>()
                
                for gateIndex in 0..<index {
                    let gate = sortedTypes[gateIndex]
                    let dependency = ActivationDependency(dependent: type, gate: gate)
                    dependencies.insert(dependency)
                    gatesForThisGesture.insert(gate)
                }
                
                // Add gate group: all gates from this gesture must be satisfied together
                if !gatesForThisGesture.isEmpty {
                    gateGroups[type, default: []].append(gatesForThisGesture)
                }
            }
        }
        
        if log.isDebugEnabled {
            log.log("ActivationCoordinator: Built \(dependencies.count) dependencies from \(gestures.count) gestures")
            for (dependent, groups) in gateGroups {
                for group in groups {
                    let gateNames = group.map { $0.displayName }.joined(separator: " AND ")
                    log.log("  - \(dependent.displayName) gated by [\(gateNames)]")
                }
            }
        }
        
        evaluateGatedActivations()
    }
    
    // MARK: - Gating Logic
    
    private func evaluateGatedActivations() {
        let usedTypes = getUsedActivationTypes()
        
        for type in ActivationType.allCases {
            // Infrastructure types always run
            if queryIsInfrastructure(for: type) {
                enableActivationType(type)
                continue
            }
            
            // Not used in any gesture → disable
            if !usedTypes.contains(type) {
                disableActivationType(type)
                continue
            }
            
            // Always-active types that ARE used don't need gating
            if queryIsAlwaysActive(for: type) {
                enableActivationType(type)
                continue
            }
            
            // Check gate groups: OR across groups, AND within each group
            // Each group represents one gesture's gate requirements
            let groups = gateGroups[type] ?? []
            
            if groups.isEmpty {
                enableActivationType(type)
            } else {
                let anyGroupFullySatisfied = groups.contains { group in
                    group.allSatisfy { gate in isGateSatisfied(gate, for: type) }
                }
                if anyGroupFullySatisfied {
                    enableActivationType(type)
                } else {
                    disableActivationType(type)
                }
            }
        }
    }
    
    /// Check if a gate is satisfied for a dependent type.
    /// Delegates precision validation to the gate's provider — no plugin-specific logic here.
    private func isGateSatisfied(_ gate: ActivationType, for dependent: ActivationType) -> Bool {
        guard isEngaged(gate) else { return false }
        
        // Ask the gate provider to validate whether its current state
        // actually warrants enabling the dependent type
        guard let provider = getProvider(for: gate) else { return true }
        let dependentGestures = gesturesPerType[dependent] ?? []
        return provider.validateGate(for: dependent, gestures: dependentGestures)
    }
    
    /// Get all activation types used in enabled gestures (queried from providers)
    private func getUsedActivationTypes() -> Set<ActivationType> {
        return Set(gesturesPerType.keys)
    }
    
    private func enableActivationType(_ type: ActivationType) {
        guard !enabledTypes.contains(type) else { return }
        
        enabledTypes.insert(type)
        
        if let provider = getProvider(for: type), !provider.isDetectionActive(for: type) {
            provider.enableDetection(for: type)
            log.log("ActivationCoordinator: Enabled \(type.displayName)")
        }
    }
    
    private func disableActivationType(_ type: ActivationType) {
        guard enabledTypes.contains(type) else { return }
        
        enabledTypes.remove(type)
        
        if activationStates[type]?.isEngaged == true {
            activationStates[type] = ActivationState(type: type, isEngaged: false, metadata: [:])
            if log.isDebugEnabled {
                log.log("ActivationCoordinator: Force-disengaged \(type.displayName) (gates no longer satisfied)")
            }
        }
        
        if let provider = getProvider(for: type), provider.isDetectionActive(for: type) {
            provider.disableDetection(for: type)
            log.log("ActivationCoordinator: Disabled \(type.displayName)")
        }
    }
    
    // MARK: - Query Methods
    
    func getActiveActivationTypes() -> Set<ActivationType> {
        lock.lock()
        defer { lock.unlock() }
        return enabledTypes
    }
    
    func getDependencies(for type: ActivationType) -> Set<ActivationType> {
        lock.lock()
        defer { lock.unlock() }
        return Set(dependencies.filter { $0.dependent == type }.map { $0.gate })
    }
    
    func getDependents(for type: ActivationType) -> Set<ActivationType> {
        lock.lock()
        defer { lock.unlock() }
        return Set(dependencies.filter { $0.gate == type }.map { $0.dependent })
    }
    
    // MARK: - Debug
    
    func debugDescription() -> String {
        lock.lock()
        defer { lock.unlock() }
        
        var desc = "ActivationCoordinator State:\n"
        desc += "Activation States:\n"
        for (type, state) in activationStates.sorted(by: { queryEfficiencyScore(for: $0.key) > queryEfficiencyScore(for: $1.key) }) {
            let engaged = state.isEngaged ? "✓" : "○"
            let active = enabledTypes.contains(type) ? "ACTIVE" : "inactive"
            let score = queryEfficiencyScore(for: type)
            desc += "  \(engaged) \(type.displayName) (efficiency: \(score)) - \(active)\n"
        }
        
        desc += "\nDependencies:\n"
        for dep in dependencies.sorted(by: { $0.dependent.rawValue < $1.dependent.rawValue }) {
            desc += "  \(dep.dependent.displayName) <- \(dep.gate.displayName)\n"
        }
        
        return desc
    }
}

// MARK: - Weak Reference Wrapper

private class Weak<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// MARK: - Convenience Extensions

extension ActivationCoordinator {
    var shouldTrackMouse: Bool {
        return enabledTypes.contains(.screenZone)
    }
    
    var hasActiveModifiers: Bool {
        return isEngaged(.modifierKey)
    }
}
