import Cocoa
import IOKit.ps
import Network
import MouseGestures

/// Passive triggers: things that happen to the Mac rather than something you do.
@objc(SystemEventsPlugin)
public final class SystemEventsPlugin: NSObject, ExternalTriggerPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.systemevents" }
    public var name: String { "System Events" }
    public var summary: String { "Sleep, wake, lock, power, network, disks, appearance, idle and app launches" }
    public var version: String { "1.2.0" }
    public var author: String { "MouseGestures" }
    public var icon: String { "bolt.badge.clock" }
    public var triggers: [ExternalTriggerDefinition] {[
        ExternalTriggerDefinition(id: "wake", name: "Mac woke from sleep"),
        ExternalTriggerDefinition(id: "will_sleep", name: "Mac is going to sleep", summary: "Runs just before sleep, so keep the action quick"),
        ExternalTriggerDefinition(id: "screen_locked", name: "Screen locked"),
        ExternalTriggerDefinition(id: "screen_unlocked", name: "Screen unlocked"),
        ExternalTriggerDefinition(id: "display_changed", name: "Display connected or removed"),
        ExternalTriggerDefinition(id: "power_plugged", name: "Power adapter plugged in"),
        ExternalTriggerDefinition(id: "power_unplugged", name: "Power adapter unplugged"),
        ExternalTriggerDefinition(id: "battery_low", name: "Battery is low", summary: "Falls below the level set in this plugin's settings, while unplugged"),
        ExternalTriggerDefinition(id: "disk_mounted", name: "Disk or drive connected"),
        ExternalTriggerDefinition(id: "disk_unmounted", name: "Disk or drive removed"),
        ExternalTriggerDefinition(id: "network_online", name: "Internet connection came back"),
        ExternalTriggerDefinition(id: "network_offline", name: "Internet connection lost"),
        ExternalTriggerDefinition(id: "dark_mode_on", name: "Switched to Dark Mode"),
        ExternalTriggerDefinition(id: "light_mode_on", name: "Switched to Light Mode"),
        ExternalTriggerDefinition(id: "idle", name: "You went idle", summary: "No keyboard or mouse input for the idle time in the settings"),
        ExternalTriggerDefinition(id: "idle_return", name: "You came back from idle"),
        ExternalTriggerDefinition(id: "app_launched", name: "Watched app launched", summary: "Name the app in this plugin's settings"),
        ExternalTriggerDefinition(id: "app_quit", name: "Watched app quit", summary: "Name the app in this plugin's settings"),
    ]}

    private weak var host: ExternalTriggerHost?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?
    private var onAC: Bool?
    private var displayDebounce: Timer?
    private var settings: PluginHost?
    private var pathMonitor: NWPathMonitor?
    private var online: Bool?
    private var pollTimer: Timer?
    private var isIdle = false
    private var batteryAlerted = false
    private var lastDark: Bool?

    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "displaySettle", title: "Display change settle time",
                           kind: .number(min: 0.5, max: 5, step: 0.5, unit: "s"), defaultValue: AnyCodable(1.0),
                           help: "Connecting a display produces several change events; the trigger fires once after this quiet period."),
        PluginSettingField(key: "idleMinutes", title: "Idle after", kind: .number(min: 1, max: 120, step: 1, unit: "min"),
                           defaultValue: AnyCodable(5), help: "No keyboard or mouse input for this long counts as idle."),
        PluginSettingField(key: "batteryPercent", title: "Battery is low at", kind: .number(min: 5, max: 50, step: 5, unit: "%"),
                           defaultValue: AnyCodable(20), help: "The “Battery is low” trigger fires once when the level drops to this while unplugged."),
        PluginSettingField(key: "watchedApp", title: "App to watch", kind: .text(placeholder: "Safari or com.apple.Safari"),
                           help: "Name or bundle identifier for the “launched” and “quit” triggers."),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    public func start(host: ExternalTriggerHost) throws {
        self.host = host
        func observe(_ center: NotificationCenter, _ name: NSNotification.Name, _ id: String, filter: ((Notification) -> Bool)? = nil) {
            tokens.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                if let filter = filter, !filter(n) { return }
                self?.host?.fire(triggerId: id)
            }))
        }
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.didWakeNotification, "wake")
        observe(ws, NSWorkspace.willSleepNotification, "will_sleep")
        observe(ws, NSWorkspace.didMountNotification, "disk_mounted")
        observe(ws, NSWorkspace.didUnmountNotification, "disk_unmounted")
        observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsLocked"), "screen_locked")
        observe(DistributedNotificationCenter.default(), .init("com.apple.screenIsUnlocked"), "screen_unlocked")
        observe(ws, NSWorkspace.didLaunchApplicationNotification, "app_launched") { [weak self] in self?.isWatched($0) ?? false }
        observe(ws, NSWorkspace.didTerminateApplicationNotification, "app_quit") { [weak self] in self?.isWatched($0) ?? false }

        // Display changes arrive in bursts; settle before firing once.
        tokens.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.displayDebounce?.invalidate()
            self?.displayDebounce = Timer.scheduledTimer(withTimeInterval: self?.settings?.number("displaySettle", default: 1.0) ?? 1.0, repeats: false) { _ in
                self?.host?.fire(triggerId: "display_changed")
            }
        }))

        // Appearance
        lastDark = Self.isDark()
        tokens.append((DistributedNotificationCenter.default(), DistributedNotificationCenter.default().addObserver(
            forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            let dark = Self.isDark()
            guard dark != self.lastDark else { return }
            self.lastDark = dark
            self.host?.fire(triggerId: dark ? "dark_mode_on" : "light_mode_on")
        }))

        // Power
        onAC = Self.isOnAC()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx = ctx else { return }
            Unmanaged<SystemEventsPlugin>.fromOpaque(ctx).takeUnretainedValue().powerChanged()
        }, ctx)?.takeRetainedValue() {
            powerSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }

        // Network
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let up = path.status == .satisfied
                defer { self.online = up }
                guard let was = self.online, was != up else { return }
                self.host?.fire(triggerId: up ? "network_online" : "network_offline")
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.mousegestures.lib.systemevents.net"))
        pathMonitor = monitor

        // Idle + battery level are polled
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        host.log("System Events started")
    }

    public func stop() {
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens.removeAll()
        if let s = powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .defaultMode) }
        powerSource = nil
        displayDebounce?.invalidate()
        pathMonitor?.cancel(); pathMonitor = nil; online = nil
        pollTimer?.invalidate(); pollTimer = nil
        host = nil
    }

    // MARK: helpers

    private func isWatched(_ n: Notification) -> Bool {
        let watch = (settings?.string("watchedApp") ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !watch.isEmpty, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return false }
        return app.bundleIdentifier?.lowercased() == watch || app.localizedName?.lowercased() == watch
    }

    private func poll() {
        // idle: seconds since any input event
        let idleFor = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let limit = (settings?.number("idleMinutes", default: 5) ?? 5) * 60
        if !isIdle, idleFor >= limit { isIdle = true; host?.fire(triggerId: "idle") }
        else if isIdle, idleFor < 5 { isIdle = false; host?.fire(triggerId: "idle_return") }

        // battery
        if let (percent, charging) = Self.battery() {
            let threshold = settings?.number("batteryPercent", default: 20) ?? 20
            if !charging, Double(percent) <= threshold, !batteryAlerted { batteryAlerted = true; host?.fire(triggerId: "battery_low") }
            else if charging || Double(percent) > threshold + 5 { batteryAlerted = false }
        }
    }

    private func powerChanged() {
        let now = Self.isOnAC()
        guard let was = onAC, was != now else { onAC = now; return }
        onAC = now
        host?.fire(triggerId: now ? "power_plugged" : "power_unplugged")
    }

    private static func isOnAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return true }
        return type == kIOPSACPowerValue
    }

    private static func battery() -> (Int, Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let state = d[kIOPSPowerSourceStateKey] as? String
            return (cur * 100 / max, state == kIOPSACPowerValue)
        }
        return nil
    }

    private static func isDark() -> Bool {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String == "Dark"
    }
}
