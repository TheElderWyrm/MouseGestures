import Cocoa
import Carbon
import UserNotifications

/// Manages the menu bar icon and its associated menu
class MenuIcon: NSObject {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var profilesMenuItem: NSMenuItem?
    private var gesturesMenuItem: NSMenuItem?
    private var licenseMenuItem: NSMenuItem?
    private weak var delegate: MenuIconDelegate?
    private let profileManager = ProfileManager.shared
    private let licenseService = LicenseService.shared

    // MARK: - Initialization

    init(delegate: MenuIconDelegate) {
        self.delegate = delegate
        super.init()

        // Listen for configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationChanged),
            name: NSNotification.Name("GestureConfigurationChanged"),
            object: nil
        )

        // Listen for profile changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(profileChanged),
            name: .profileDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(profilesListChanged),
            name: .profilesDidChange,
            object: nil
        )

        // Listen for license changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(licenseChanged),
            name: NSNotification.Name("LicenseStatusChanged"),
            object: nil
        )

        // Check initial visibility
        updateVisibility()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        hide()
    }

    // MARK: - Public Methods

    /// Shows the menu bar icon if it's not already visible
    func show() {
        guard statusItem == nil else { return }

        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        applyDisplayStyle()

        // Create menu
        let menu = NSMenu()

        // Preferences menu item
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        // Add profiles submenu
        let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        let profilesSubmenu = NSMenu()
        profilesItem.submenu = profilesSubmenu
        menu.addItem(profilesItem)
        profilesMenuItem = profilesItem
        updateProfilesMenu()

        // Add gestures submenu
        let currentGesturesItem = NSMenuItem(title: "Gestures", action: nil, keyEquivalent: "")
        let gesturesSubmenu = NSMenu()
        currentGesturesItem.submenu = gesturesSubmenu
        menu.addItem(currentGesturesItem)
        gesturesMenuItem = currentGesturesItem
        updateGesturesMenu()

        // License status item
        let licenseItem = NSMenuItem(title: "License: ...", action: nil, keyEquivalent: "")
        licenseItem.isEnabled = false // Greys it out
        menu.addItem(licenseItem)
        self.licenseMenuItem = licenseItem
        updateLicenseMenu()

        menu.addItem(NSMenuItem.separator())

        // Check Accessibility Permissions menu item
        let checkPermissionsItem = NSMenuItem(title: "Check Accessibility Permissions", action: #selector(checkPermissions), keyEquivalent: "")
        checkPermissionsItem.target = self
        menu.addItem(checkPermissionsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit menu item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // Update initial states
        updateGestureToggleState()
        updateAppearance()
    }

    /// Hides the menu bar icon
    func hide() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        profilesMenuItem = nil
    }

    /// Updates the appearance of the menu bar icon based on current state
    func updateAppearance() {
        let work = { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }

            self.applyDisplayStyle()

            let hasPermission = self.delegate?.menuIconRequestsAccessibilityStatus() ?? false
            let gesturesEnabled = self.delegate?.menuIconRequestsGestureEnabledState() ?? false

            if !hasPermission {
                // Show warning state if no permissions
                button.appearsDisabled = true
                button.toolTip = "MouseGestures requires accessibility permissions"
            } else if gesturesEnabled {
                button.appearsDisabled = false
                button.toolTip = "MouseGestures - Gestures Enabled"
            } else {
                button.appearsDisabled = true
                button.toolTip = "MouseGestures - Gestures Disabled"
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Sets the status item's image according to `Configuration.shared.menuBarIconOption`.
    private func applyDisplayStyle() {
        guard let button = statusItem?.button else { return }
        button.title = ""

        let config = Configuration.shared
        if config.menuBarIconOption == .custom, let data = config.customMenuBarIconData, let custom = NSImage(data: data) {
            custom.size = NSSize(width: 18, height: 18)
            custom.isTemplate = config.customMenuBarIconIsTemplate
            button.image = custom
            return
        }

        let symbolName = config.menuBarIconOption.symbolName ?? "hand.draw"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Mouse Gestures")
        button.image?.isTemplate = true
    }

    /// Updates the state of menu items based on accessibility permissions
    func updateAccessibilityState(hasPermission: Bool) {
        let work = { [weak self] in
            guard let self = self, let menu = self.statusItem?.menu else { return }

            // Enable/disable the toggle gestures item based on permission
            if let toggleItem = menu.item(withTitle: "Enable Gestures") {
                toggleItem.isEnabled = hasPermission
                if !hasPermission {
                    toggleItem.state = .off
                }
            }

            self.updateAppearance()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Updates the gesture toggle menu item state
    func updateGestureToggleState() {
        let work = { [weak self] in
            guard let self = self,
                  let menu = self.statusItem?.menu,
                  let toggleItem = menu.item(withTitle: "Enable Gestures") else { return }

            let isEnabled = self.delegate?.menuIconRequestsGestureEnabledState() ?? false
            toggleItem.state = isEnabled ? .on : .off
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Private Methods

    private func updateVisibility() {
        let config = Configuration.shared
        if config.hideFromMenuBar {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Menu Actions

    @objc private func showPreferences() {
        delegate?.menuIconDidSelectPreferences()
    }

    @objc private func toggleGestures() {
        // Check permissions before toggling
        let hasPermission = delegate?.menuIconRequestsAccessibilityStatus() ?? false

        if !hasPermission {
            delegate?.menuIconRequestsAccessibilityAlert()
            return
        }

        delegate?.menuIconDidToggleGestures()
        updateGestureToggleState()
        updateAppearance()
    }

    @objc private func checkPermissions() {
        delegate?.menuIconDidSelectCheckPermissions()
    }

    private func updateLicenseMenu() {
        guard let item = licenseMenuItem else { return }

        let status = licenseService.status
        let title: String

        switch status {
        case .pro:
            title = "License: Pro"
        case .trial:
            title = "License: Trial (\(licenseService.trialDaysRemaining) days left)"
        case .expired, .free:
            title = "License: Free"
        }

        item.title = title
    }

    private func updateGesturesMenu() {
        guard let submenu = gesturesMenuItem?.submenu else { return }
        submenu.removeAllItems()

        guard let activeProfile = profileManager.activeProfile else {
            let item = NSMenuItem(title: "No active profile", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
            return
        }

        let gestures = activeProfile.gestures

        if gestures.isEmpty {
            let item = NSMenuItem(title: "No gestures in this profile", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
            return
        }

        for gesture in gestures {
            let actionName = PluginManager.shared.getAction(identifier: gesture.actionIdentifier)?.action.name ?? "Unknown Action"
            let name = (gesture.name ?? "").isEmpty ? actionName : gesture.name!
            let activationText = gesture.displayDescription

            // Format: Title: (Activation) -> (Action)
            // Activation is the trigger (zone, modifiers, etc)
            // Action is the display name of the action being triggered
            let title = "\(name): (\(activationText)) -> (\(actionName))"
            let item = NSMenuItem(title: title, action: #selector(gestureMenuItemAction), keyEquivalent: "")
            item.target = self
            submenu.addItem(item)
        }
    }

    @objc private func gestureMenuItemAction() {
        // No-op - just to keep items enabled
    }

    @objc private func licenseChanged() {
        let work = { [weak self] in
            guard let self = self else { return }
            self.updateLicenseMenu()
            self.updateAppearance()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Profile Management

    private func updateProfilesMenu() {
        guard let submenu = profilesMenuItem?.submenu else { return }

        // Clear existing items
        submenu.removeAllItems()

        let profiles = profileManager.sortedProfiles
        let activeProfileId = profileManager.activeProfileId

        // Add profile items
        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(switchToProfile(_:)), keyEquivalent: "")
            item.representedObject = profile.id
            item.target = self

            // Check if this is the active profile
            if profile.id == activeProfileId {
                item.state = .on
            }

            submenu.addItem(item)
        }

        // Add separator and quick actions
        if !profiles.isEmpty {
            submenu.addItem(NSMenuItem.separator())
        }

        let nextProfileItem = NSMenuItem(title: "Next Profile", action: #selector(switchToNextProfile), keyEquivalent: "")
        nextProfileItem.target = self
        submenu.addItem(nextProfileItem)

        let prevProfileItem = NSMenuItem(title: "Previous Profile", action: #selector(switchToPreviousProfile), keyEquivalent: "")
        prevProfileItem.target = self
        submenu.addItem(prevProfileItem)
    }

    @objc private func switchToProfile(_ sender: NSMenuItem) {
        guard let profileId = sender.representedObject as? UUID else { return }
        profileManager.switchToProfile(withId: profileId)
    }

    @objc private func switchToNextProfile() {
        profileManager.switchToNextProfile()
    }

    @objc private func switchToPreviousProfile() {
        profileManager.switchToPreviousProfile()
    }

    @objc private func configurationChanged() {
        let work = { [weak self] in
            guard let self = self else { return }
            self.updateVisibility()
            if self.statusItem != nil {
                self.updateProfilesMenu()
                self.updateGesturesMenu()
                self.updateLicenseMenu()
                self.updateGestureToggleState()
                self.updateAppearance()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    @objc private func profileChanged() {
        let work: () -> Void = { [weak self] in
            self?.updateProfilesMenu()
            self?.updateGesturesMenu()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    @objc private func profilesListChanged() {
        let work: () -> Void = { [weak self] in
            self?.updateProfilesMenu()
            self?.updateGesturesMenu()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}

// MARK: - MenuIconDelegate Protocol

protocol MenuIconDelegate: AnyObject {
    /// Called when the user selects "Preferences..." from the menu
    func menuIconDidSelectPreferences()

    /// Called when the user toggles gestures on/off
    func menuIconDidToggleGestures()

    /// Called when the user selects "Check Accessibility Permissions"
    func menuIconDidSelectCheckPermissions()

    /// Requests the current accessibility permission status
    func menuIconRequestsAccessibilityStatus() -> Bool

    /// Requests to show the accessibility alert
    func menuIconRequestsAccessibilityAlert()

    /// Requests the current gesture enabled state
    func menuIconRequestsGestureEnabledState() -> Bool
}
