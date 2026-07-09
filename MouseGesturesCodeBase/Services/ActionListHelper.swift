import Cocoa

// MARK: - Plugin Action Selection Helper

/// Helper for creating action selection popup menus using the plugin system
class ActionListHelper {

    // MARK: - Action Selection

    /// Setup action popup with all available plugin actions, loaded dynamically.
    static func setupActionPopup(_ popup: NSPopUpButton, excludeBundleActions: Bool = false) {
        popup.removeAllItems()

        let pluginManager = PluginManager.shared
        let allActionsByCategory = getAllAvailableActions(from: pluginManager)

        // Group actions by category
        for (category, actions) in allActionsByCategory {
            // Add category header
            popup.addItem(withTitle: "— \(category.displayName) —")
            popup.lastItem?.isEnabled = false

            // Add actions in this category
            for (plugin, action) in actions {
                // Skip bundle actions if requested
                if excludeBundleActions && action.id.contains("bundle") {
                    continue
                }

                popup.addItem(withTitle: action.name)
                // Store the full action identifier as represented object
                popup.lastItem?.representedObject = "\(plugin.identifier).\(action.id)"

                // Add icon if available
                if let iconName = action.icon,
                   let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                    popup.lastItem?.image = image
                    popup.lastItem?.image?.size = NSSize(width: 16, height: 16)
                }
            }
        }

        // Add saved actions if available
        let savedActions = SavedActionsManager.shared.savedActions
        if !savedActions.isEmpty {
            popup.addItem(withTitle: "— Saved Actions —")
            popup.lastItem?.isEnabled = false

            for savedAction in savedActions {
                let title = "Use: \(savedAction.name)"
                popup.addItem(withTitle: title)
                popup.lastItem?.representedObject = savedAction.id
            }
        }
    }

    /// Find the action identifier for a given popup title
    static func actionIdentifierForTitle(_ title: String, in popup: NSPopUpButton) -> String? {
        if let item = popup.item(withTitle: title),
           let identifier = item.representedObject as? String {
            return identifier
        }
        return nil
    }

    /// Get the plugin action for a given identifier
    static func getAction(for identifier: String) -> PluginAction? {
        let pluginManager = PluginManager.shared
        if let (_, action) = pluginManager.getAction(identifier: identifier) {
            return action
        }
        return nil
    }

    /// Check if an action requires parameters
    static func actionRequiresConfiguration(_ identifier: String) -> Bool {
        guard let action = getAction(for: identifier) else { return false }
        return action.requiresParameters
    }

    /// Get configuration view for an action
    static func getConfigurationView(for identifier: String) -> NSView? {
        let pluginManager = PluginManager.shared
        return pluginManager.getConfigurationView(for: identifier)
    }

    /// Get all available actions from plugins, grouped by category
    private static func getAllAvailableActions(from pluginManager: PluginManager) -> [(category: ActionCategory, actions: [(plugin: GestureActionPlugin, action: PluginAction)])] {
        var result: [(ActionCategory, [(plugin: GestureActionPlugin, action: PluginAction)])] = []

        for category in ActionCategory.allCases {
            let actions = pluginManager.getActionsForCategory(category)
            if !actions.isEmpty {
                result.append((category, actions))
            }
        }

        return result
    }
}

// MARK: - Action Category Extension

extension ActionCategory {
    var displayName: String {
        return self.rawValue
    }
}
