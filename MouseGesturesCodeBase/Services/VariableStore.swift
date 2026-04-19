import Foundation

// MARK: - Variable Store

/// Thread-safe store for user-defined variables.
///
/// Variables are set via the "Set Variable" action and accessed in any action parameter
/// using the `{VARIABLE_NAME}` token syntax (e.g. `{my_url}`, `{target_app}`).
///
/// Values persist across app restarts via UserDefaults.
class VariableStore {

    static let shared = VariableStore()

    private let queue = DispatchQueue(label: "com.mousegestures.variablestore", attributes: .concurrent)
    private var variables: [String: String] = [:]
    private let defaultsKey = "com.mousegestures.userVariables"

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] {
            variables = saved
        }
    }

    // MARK: - Access

    func set(_ name: String, value: String) {
        queue.async(flags: .barrier) {
            self.variables[name] = value
            self.persist()
        }
    }

    func get(_ name: String) -> String? {
        return queue.sync { variables[name] }
    }

    func getAll() -> [String: String] {
        return queue.sync { variables }
    }

    func remove(_ name: String) {
        queue.async(flags: .barrier) {
            self.variables.removeValue(forKey: name)
            self.persist()
        }
    }

    func clear() {
        queue.async(flags: .barrier) {
            self.variables.removeAll()
            self.persist()
        }
    }

    // MARK: - Persistence

    private func persist() {
        let snapshot = variables
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }
}
