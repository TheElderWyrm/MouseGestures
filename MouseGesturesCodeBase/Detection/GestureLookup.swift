import Cocoa

/// Manages efficient gesture lookup using hash tables for O(1) performance
class GestureLookup {
    
    // MARK: - Properties
    
    // Performance optimization: Gesture lookup table for O(1) access
    private var lookupTable: [String: [Gesture]] = [:]
    private var lastConfigurationHash: Int = 0
    
    // MARK: - Initialization
    
    init() {
        // Build initial lookup table
        rebuild()
        
        // Listen for configuration changes to rebuild the table
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
    
    // MARK: - Public Methods
    
    /// Finds matching gestures for the given parameters
    /// - Parameters:
    ///   - zone: The screen zone
    ///   - dragModifier: The drag state
    ///   - modifiers: The keyboard modifiers
    /// - Returns: Array of matching gestures (may be empty)
    func findMatchingGestures(zone: ScreenZone, dragModifier: DragModifier, modifiers: NSEvent.ModifierFlags) -> [Gesture] {
        let key = createLookupKey(zone: zone, dragModifier: dragModifier, modifiers: modifiers)
        return lookupTable[key] ?? []
    }
    
    /// Rebuilds the lookup table from current configuration
    func rebuild() {
        lookupTable.removeAll()
        
        let gestures = Configuration.shared.gestures
        var addedCount = 0
        
        // Build lookup table with composite keys for O(1) access
        for gesture in gestures where gesture.isEnabled {
            // Only include gestures that can be triggered by zone/drag/modifiers
            if shouldIncludeGesture(gesture) {
                let key = createLookupKey(
                    zone: gesture.zone,
                    dragModifier: gesture.dragModifier,
                    modifiers: gesture.modifiers
                )
                lookupTable[key, default: []].append(gesture)
                addedCount += 1
            }
        }
        
        if log.isDebugEnabled {
            log.log("GestureLookup: Rebuilt table with \(lookupTable.count) unique combinations, \(addedCount) total gestures")
        }
    }
    
    /// Clears the lookup table
    func clear() {
        lookupTable.removeAll()
        log.log("GestureLookup: Cleared lookup table")
    }
    
    /// Returns statistics about the lookup table
    func getStatistics() -> (uniqueCombinations: Int, totalGestures: Int) {
        let uniqueCombinations = lookupTable.count
        let totalGestures = lookupTable.values.reduce(0) { $0 + $1.count }
        return (uniqueCombinations, totalGestures)
    }
    
    // MARK: - Private Methods
    
    /// Determines if a gesture should be included in the lookup table
    private func shouldIncludeGesture(_ gesture: Gesture) -> Bool {
        // Include gestures that can be triggered by zone/drag/modifier combinations
        return gesture.activationType == .gesture ||
               gesture.activationType == .both ||
               gesture.activationType == .gestureMouseButton ||
               gesture.activationType == .all
    }
    
    /// Creates a lookup key for the given parameters
    private func createLookupKey(zone: ScreenZone, dragModifier: DragModifier, modifiers: NSEvent.ModifierFlags) -> String {
        let normalizedModifiers = normalizeModifiers(modifiers)
        // Key format: "zone_dragModifier_modifiers"
        return "\(zone.rawValue)_\(dragModifier.rawValue)_\(normalizedModifiers.rawValue)"
    }
    
    /// Normalizes modifier flags to only include the ones we care about
    private func normalizeModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var normalized: NSEvent.ModifierFlags = []
        if flags.contains(.command) { normalized.insert(.command) }
        if flags.contains(.control) { normalized.insert(.control) }
        if flags.contains(.option) { normalized.insert(.option) }
        if flags.contains(.shift) { normalized.insert(.shift) }
        return normalized
    }
    
    /// Called when configuration changes
    @objc private func configurationChanged() {
        rebuild()
    }
}

// MARK: - Performance Extensions

extension GestureLookup {
    
    /// Preloads gestures for common modifier combinations to optimize performance
    func preloadCommonCombinations() {
        // This could be expanded to pre-cache common combinations
        // Currently the lookup is already O(1) so this may not be necessary
    }
    
    /// Returns debug information about the lookup table
    func debugDescription() -> String {
        var description = "GestureLookup Debug Info:\n"
        description += "Total combinations: \(lookupTable.count)\n"
        
        // Show distribution of gestures per combination
        var distribution: [Int: Int] = [:]
        for gestures in lookupTable.values {
            distribution[gestures.count, default: 0] += 1
        }
        
        description += "Distribution:\n"
        for (count, occurrences) in distribution.sorted(by: { $0.key < $1.key }) {
            description += "  \(count) gesture(s): \(occurrences) combination(s)\n"
        }
        
        return description
    }
}

// MARK: - Static Convenience Methods

extension GestureLookup {
    
    /// Shared instance for global access (optional - can be removed if not needed)
    static let shared = GestureLookup()
    
    /// Quick lookup without creating an instance
    static func quickLookup(zone: ScreenZone, dragModifier: DragModifier, modifiers: NSEvent.ModifierFlags) -> [Gesture] {
        return shared.findMatchingGestures(zone: zone, dragModifier: dragModifier, modifiers: modifiers)
    }
}
