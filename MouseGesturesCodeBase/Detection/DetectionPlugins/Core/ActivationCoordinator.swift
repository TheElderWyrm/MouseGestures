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
    
    // REMOVED: gestureUsesActivation - moved to ActivationMapper
    // Detection plugins no longer need to understand gesture structure
    
    /// Optional: Provide custom metadata for gate validation.
    /// Plugins can return current state details (e.g., which modifiers are held)
    /// that the ActivationMapper can use for precision gating.
    func getGateValidationMetadata() -> [String: Any]
}

// MARK: - Default Implementations

extension ActivationProvider {
    func efficiencyScore(for type: ActivationType) -> Int { return 50 }
    func isAlwaysActive(for type: ActivationType) -> Bool { return efficiencyScore(for: type) >= 70 }
    func isInfrastructure(for type: ActivationType) -> Bool { return false }
    
    func getGateValidationMetadata() -> [String: Any] {
        // Default: no additional metadata
        return [:]
    }
}

// MARK: - Component UI Provider Extension

/// Extension to support dynamic UI generation for activation components
extension ActivationProvider {
    /// Get UI metadata for components this plugin provides
    /// Plugins can override to provide custom UI configuration
    func getComponentUIMetadata() -> [ActivationComponentUIMetadata] {
        // Default: no UI metadata
        return []
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
    
    /// Get activation types a gesture uses (via central mapper)
    private func queryActivationTypes(for gesture: Gesture) -> Set<ActivationType> {
        return ActivationMapper.shared.activationTypes(for: gesture)
    }
    
    // MARK: - Dependency Management
    
    @objc func configurationChanged() {
        rebuildDependencies()
    }
    
    func rebuildDependencies() {
        let t = CFAbsoluteTimeGetCurrent()
        lock.lock()
        defer {
            lock.unlock()
            NSLog("[PROFILE-DEBUG] ActivationCoordinator.rebuildDependencies: %.1fms", (CFAbsoluteTimeGetCurrent() - t) * 1000)
        }
        
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
            
            // Build efficiency chain for this gesture.
            // Infrastructure types are excluded (always unconditionally active).
            // Every other type participates in the chain regardless of efficiency.
            let chainTypes = usedTypes
                .filter { !queryIsInfrastructure(for: $0) }
                .sorted { queryEfficiencyScore(for: $0) > queryEfficiencyScore(for: $1) }
            
            guard !chainTypes.isEmpty else { continue }
            
            // The most efficient type in this gesture's chain has no prerequisites —
            // mark it unconditionally needed (empty gate group always passes).
            gateGroups[chainTypes[0], default: []].append(Set<ActivationType>())
            
            // Each subsequent type is gated by ALL more-efficient predecessors.
            // AND-within ensures the full chain of prerequisites must be satisfied.
            for index in 1..<chainTypes.count {
                let type = chainTypes[index]
                let gates = Set(chainTypes[0..<index])
                
                gateGroups[type, default: []].append(gates)
                
                for gate in gates {
                    dependencies.insert(ActivationDependency(dependent: type, gate: gate))
                }
            }
        }
        
        if log.isDebugEnabled {
            log.log("ActivationCoordinator: Built \(dependencies.count) dependencies from \(gestures.count) gestures")
            for (dependent, groups) in gateGroups {
                for group in groups {
                    if group.isEmpty {
                        log.log("  - \(dependent.displayName): unconditional (top of chain)")
                    } else {
                        let gateNames = group.map { $0.displayName }.joined(separator: " AND ")
                        log.log("  - \(dependent.displayName) gated by [\(gateNames)]")
                    }
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
            
            // Check gate groups: OR across groups, AND within each group.
            // Each group represents one gesture's chain requirements.
            // An empty group (from top-of-chain) always passes, keeping the
            // type unconditionally active when any gesture needs it ungated.
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
    /// Uses ActivationMapper for precision validation instead of asking plugins.
    private func isGateSatisfied(_ gate: ActivationType, for dependent: ActivationType) -> Bool {
        guard isEngaged(gate) else { return false }
        
        // Use mapper for precision validation based on gate type
        guard let provider = getProvider(for: gate) else { return true }
        let metadata = provider.getGateValidationMetadata()
        let dependentGestures = gesturesPerType[dependent] ?? []
        
        // Mapper handles the gesture inspection logic
        return validateGateWithMapper(gate: gate, dependent: dependent, 
                                     metadata: metadata, gestures: dependentGestures)
    }
    
    /// Perform precision gate validation using ActivationMapper
    private func validateGateWithMapper(gate: ActivationType, dependent: ActivationType,
                                       metadata: [String: Any], gestures: [Gesture]) -> Bool {
        switch gate {
        case .modifierKey:
            // Check if held modifiers match any gesture requiring the dependent type
            if let modifierFlags = metadata["modifiers"] as? UInt,
               dependent == .screenZone {
                let mods = NSEvent.ModifierFlags(rawValue: modifierFlags)
                return ActivationMapper.shared.heldModifiersMatchGestures(mods, 
                    dependentType: dependent, gestures: gestures)
            }
            return true
            
        case .mouseButton:
            // Check if held button matches any gesture requiring the dependent type
            if let buttonRaw = metadata["heldButton"] as? String,
               let button = MouseButtonTrigger.MouseButton(rawValue: buttonRaw),
               dependent == .screenZone {
                return ActivationMapper.shared.heldButtonMatchesGestures(button, 
                    gestures: gestures)
            }
            return true
            
        default:
            // Other gate types don't need precision validation
            return true
        }
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
