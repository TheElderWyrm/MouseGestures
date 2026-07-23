import Foundation

// MARK: - Saved Action Model (Plugin-based)

struct SavedAction: Codable, Identifiable {
    let id: UUID
    var name: String
    let actionIdentifier: String // e.g., "com.mousegestures.core.close_window"
    var parameters: [String: AnyCodable]
    let dateCreated: Date
    var dateModified: Date

    var displayName: String {
        return name
    }

    var typeDisplayName: String {
        // Get the category from the plugin that provides the action
        if let (plugin, _) = PluginManager.shared.getAction(identifier: actionIdentifier) {
            return plugin.category.displayName
        }
        return "Unknown"
    }

    var description: String {
        // Get the action's description from the plugin
        if let (_, action) = PluginManager.shared.getAction(identifier: actionIdentifier) {
            return action.description
        }
        return "No description available."
    }

    init(id: UUID = UUID(),
         name: String,
         actionIdentifier: String,
         parameters: [String: AnyCodable] = [:],
         dateCreated: Date = Date(),
         dateModified: Date = Date()) {
        self.id = id
        self.name = name
        self.actionIdentifier = actionIdentifier
        self.parameters = parameters
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }
}

// MARK: - Saved Actions Manager

class SavedActionsManager {
    static let shared = SavedActionsManager()

    private let userDefaults = UserDefaults.standard
    private let savedActionsKey = "SavedActions"

    private(set) var savedActions: [SavedAction] = []

    private init() {
        loadSavedActions()
    }

    // MARK: - CRUD Operations

    func addAction(_ action: SavedAction) {
        savedActions.append(action)
        saveToDisk()
        log.log("Added saved action: \(action.name) with action \(action.actionIdentifier)")
    }

    func updateAction(_ action: SavedAction) {
        if let index = savedActions.firstIndex(where: { $0.id == action.id }) {
            var updatedAction = action
            updatedAction.dateModified = Date()
            savedActions[index] = updatedAction
            saveToDisk()
            log.log("Updated saved action: \(action.name)")
        }
    }

    func deleteAction(_ action: SavedAction) {
        savedActions.removeAll { $0.id == action.id }
        saveToDisk()
        log.log("Deleted saved action: \(action.name)")
    }

    func clearAll() {
        savedActions.removeAll()
        saveToDisk()
        log.log("Cleared all saved actions")
    }

    func getAction(byId id: UUID) -> SavedAction? {
        return savedActions.first { $0.id == id }
    }

    // MARK: - Persistence

    private func loadSavedActions() {
        if let data = userDefaults.data(forKey: savedActionsKey),
           let actions = try? JSONDecoder().decode([SavedAction].self, from: data) {
            savedActions = actions
            log.log("Loaded \(actions.count) saved actions")
        }
    }

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(savedActions) {
            userDefaults.set(data, forKey: savedActionsKey)
            log.log("Saved \(savedActions.count) actions to disk")
            // Post notification that saved actions have changed
            NotificationCenter.default.post(name: Notification.Name("savedActionsDidChange"), object: nil)
        }
    }

    // MARK: - Export/Import

    func exportAction(_ action: SavedAction) -> Data? {
        return try? JSONEncoder().encode(action)
    }

    func importAction(from data: Data) -> SavedAction? {
        if let action = try? JSONDecoder().decode(SavedAction.self, from: data) {
            // Assign a new ID to avoid conflicts
            let newAction = SavedAction(
                id: UUID(),
                name: action.name,
                actionIdentifier: action.actionIdentifier,
                parameters: action.parameters,
                dateCreated: action.dateCreated,
                dateModified: Date()
            )
            return newAction
        }
        return nil
    }

    func exportAllActions() -> Data? {
        return try? JSONEncoder().encode(savedActions)
    }

    func importActions(from data: Data, replaceExisting: Bool = false) -> Bool {
        if let importedActions = try? JSONDecoder().decode([SavedAction].self, from: data) {
            if replaceExisting {
                savedActions = importedActions
            } else {
                // Merge with existing, avoiding duplicates by name AND id.
                for action in importedActions {
                    if !savedActions.contains(where: { $0.name == action.name || $0.id == action.id }) {
                        // Always mint a fresh id on import. The single-action
                        // import path does this; the bulk path previously reused
                        // the imported id, which could collide with an existing
                        // action (same id, different name) and make getAction /
                        // updateAction / deleteAction operate on the wrong row.
                        let newAction = SavedAction(
                            id: UUID(),
                            name: action.name,
                            actionIdentifier: action.actionIdentifier,
                            parameters: action.parameters,
                            dateCreated: action.dateCreated,
                            dateModified: Date()
                        )
                        savedActions.append(newAction)
                    }
                }
            }
            saveToDisk()
            return true
        }
        return false
    }
}
