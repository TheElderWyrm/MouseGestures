import Cocoa

/// Manages efficient gesture lookup using hash tables for O(1) performance
class GestureLookup {

    // MARK: - Properties

    // Performance optimization: Gesture lookup table for O(1) access
    private var lookupTable: [String: [Gesture]] = [:]
    private var lastConfigurationHash: Int = 0

    // Guards `lookupTable`. rebuild() is driven by a "GestureConfigurationChanged"
    // observer whose callback runs on whatever thread posted the notification —
    // that can be the action-execution queue (PluginSandbox.postNotification), NOT
    // main — while findMatchingGestures() runs on the main event-monitor thread.
    // A concurrent Dictionary read+mutate corrupts the heap, so serialize both.
    private let lock = NSLock()

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
        // When a specific drag is active, also check anyDrag gestures
        let anyDragKey = (dragModifier != .none && dragModifier != .anyDrag)
            ? createLookupKey(zone: zone, dragModifier: .anyDrag, modifiers: modifiers)
            : nil

        lock.lock()
        defer { lock.unlock() }
        var results = lookupTable[key] ?? []
        if let anyDragKey = anyDragKey {
            results += lookupTable[anyDragKey] ?? []
        }
        return results
    }

    /// Rebuilds the lookup table from current configuration
    func rebuild() {
        // Build the new table off-lock (Configuration.shared.gestures does its own
        // configQueue.sync, and shouldIncludeGesture consults ActivationMapper —
        // neither needs, and shouldn't be serialized behind, this lock). Only the
        // final swap touches shared state under the lock.
        let gestures = Configuration.shared.gestures
        var newTable: [String: [Gesture]] = [:]
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
                newTable[key, default: []].append(gesture)
                addedCount += 1
            }
        }

        lock.lock()
        lookupTable = newTable
        lock.unlock()

        if log.isDebugEnabled {
            log.log("GestureLookup: Rebuilt table with \(newTable.count) unique combinations, \(addedCount) total gestures")
        }
    }

    /// Clears the lookup table
    func clear() {
        lock.lock()
        lookupTable.removeAll()
        lock.unlock()
        log.log("GestureLookup: Cleared lookup table")
    }

    /// Returns statistics about the lookup table
    func getStatistics() -> (uniqueCombinations: Int, totalGestures: Int) {
        lock.lock()
        defer { lock.unlock() }
        let uniqueCombinations = lookupTable.count
        let totalGestures = lookupTable.values.reduce(0) { $0 + $1.count }
        return (uniqueCombinations, totalGestures)
    }

    // MARK: - Private Methods

    /// Determines if a gesture should be included in the lookup table
    private func shouldIncludeGesture(_ gesture: Gesture) -> Bool {
        // Use ActivationMapper to determine if gesture uses zones
        // (single source of truth for gesture→activation mapping)
        return ActivationMapper.shared.activationTypes(for: gesture).contains(.screenZone)
    }

    /// Creates a lookup key for the given parameters
    private func createLookupKey(zone: ScreenZone, dragModifier: DragModifier, modifiers: NSEvent.ModifierFlags) -> String {
        // Key format: "zone_dragModifier_modifiers"
        return "\(zone.rawValue)_\(dragModifier.rawValue)_\(modifiers.normalized.rawValue)"
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
        lock.lock()
        let snapshot = lookupTable
        lock.unlock()

        var description = "GestureLookup Debug Info:\n"
        description += "Total combinations: \(snapshot.count)\n"

        // Show distribution of gestures per combination
        var distribution: [Int: Int] = [:]
        for gestures in snapshot.values {
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
