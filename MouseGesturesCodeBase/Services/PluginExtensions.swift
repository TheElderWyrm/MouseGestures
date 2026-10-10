import Foundation
import Cocoa
import SwiftUI

// MARK: - Plugin Extension SDK
// Optional capabilities ANY library plugin (action or detection) can add by also
// conforming to `PluginExtension`:
//   • settings    — declare `settingsFields`; the app renders the form, persists the
//                   values and calls `settingChanged`. Read them through the host.
//   • services    — set `runsBackgroundService`; `startService`/`stopService` run for as
//                   long as the plugin is loaded and its service switch is on.
//   • UI          — `makeSettingsView()` returns a custom NSView shown in the plugin's
//                   settings sheet, below the generated form.

public struct PluginSettingChoice: Equatable {
    public let value: String
    public let label: String
    public init(_ value: String, _ label: String) { self.value = value; self.label = label }
}

public struct PluginSettingField {
    public enum Kind {
        case toggle
        case text(placeholder: String?)
        case number(min: Double, max: Double, step: Double, unit: String?)
        case choice([PluginSettingChoice])
        case path(directoriesOnly: Bool)
        /// Read-only explanatory text (uses `title` as a heading, `help` as the body).
        case info
    }

    public let key: String
    public let title: String
    public let help: String
    public let kind: Kind
    public let defaultValue: AnyCodable?

    public init(key: String, title: String, kind: Kind, defaultValue: AnyCodable? = nil, help: String = "") {
        self.key = key; self.title = title; self.kind = kind; self.defaultValue = defaultValue; self.help = help
    }
}

/// What the app gives a plugin to work with. Safe to use from any thread.
public protocol PluginHost: AnyObject {
    var pluginId: String { get }
    /// Private, persistent folder for the plugin's own files.
    var storageDirectory: URL { get }
    /// Current value of a declared setting (the stored value, else its default).
    func setting(_ key: String) -> Any?
    func setSetting(_ key: String, to value: Any?)
    func log(_ message: String)
    func notify(title: String, message: String)
    func executeAction(identifier: String, parameters: ActionParameters) throws
}

public extension PluginHost {
    func bool(_ key: String, default d: Bool = false) -> Bool {
        if let b = setting(key) as? Bool { return b }
        if let n = setting(key) as? NSNumber { return n.boolValue }
        return d
    }
    func number(_ key: String, default d: Double = 0) -> Double {
        (setting(key) as? NSNumber)?.doubleValue ?? d
    }
    func string(_ key: String, default d: String = "") -> String { setting(key) as? String ?? d }
}

public protocol PluginExtension: AnyObject {
    var settingsFields: [PluginSettingField] { get }
    var runsBackgroundService: Bool { get }
    var hasCustomSettingsView: Bool { get }

    /// Called once right after the plugin loads (and before any service starts).
    func pluginAttached(host: PluginHost)
    /// Called when the plugin is unloaded or removed.
    func pluginDetached()
    func startService() throws
    func stopService()
    /// A setting changed (from the settings sheet or via `host.setSetting`). Main thread.
    func settingChanged(key: String, value: Any?)
    /// Custom UI for the settings sheet. Called each time the sheet opens. Main thread.
    func makeSettingsView() -> NSView?
}

public extension PluginExtension {
    var settingsFields: [PluginSettingField] { [] }
    var runsBackgroundService: Bool { false }
    var hasCustomSettingsView: Bool { false }
    func pluginAttached(host: PluginHost) {}
    func pluginDetached() {}
    func startService() throws {}
    func stopService() {}
    func settingChanged(key: String, value: Any?) {}
    func makeSettingsView() -> NSView? { nil }
}

// MARK: - Settings store

/// Per-plugin settings persisted as JSON in `PluginSettings/<id>.json`.
final class PluginSettingsStore {
    static let shared = PluginSettingsStore()
    static let serviceEnabledKey = "__serviceEnabled"

    private let lock = NSLock()
    private var cache: [String: [String: AnyCodable]] = [:]
    private let directory = Configuration.applicationSupportDirectory.appendingPathComponent("PluginSettings", isDirectory: true)

    private func file(_ id: String) -> URL { directory.appendingPathComponent("\(id).json") }

    private func load(_ id: String) -> [String: AnyCodable] {
        if let c = cache[id] { return c }
        let v = (try? Data(contentsOf: file(id))).flatMap { try? JSONDecoder().decode([String: AnyCodable].self, from: $0) } ?? [:]
        cache[id] = v
        return v
    }

    func value(_ id: String, _ key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return load(id)[key]?.value
    }

    func set(_ id: String, _ key: String, _ value: Any?) {
        lock.lock(); defer { lock.unlock() }
        var all = load(id)
        if let value = value { all[key] = AnyCodable(value) } else { all.removeValue(forKey: key) }
        cache[id] = all
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: file(id), options: .atomic) }
    }

    func removeAll(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        cache[id] = nil
        try? FileManager.default.removeItem(at: file(id))
    }
}

// MARK: - Host + manager

final class PluginHostImpl: PluginHost {
    let pluginId: String
    private let pluginName: String
    weak var manager: PluginExtensionManager?
    weak var ext: PluginExtension?

    init(pluginId: String, name: String) { self.pluginId = pluginId; self.pluginName = name }

    var storageDirectory: URL {
        let url = Configuration.applicationSupportDirectory
            .appendingPathComponent("PluginData", isDirectory: true).appendingPathComponent(pluginId, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func setting(_ key: String) -> Any? {
        if let v = PluginSettingsStore.shared.value(pluginId, key) { return v }
        return ext?.settingsFields.first { $0.key == key }?.defaultValue?.value
    }

    func setSetting(_ key: String, to value: Any?) { manager?.setSetting(pluginId, key, value) }
    func log(_ message: String) { MouseGestures.log.log("[Plugin:\(pluginId)] \(message)") }

    func notify(title: String, message: String) {
        DispatchQueue.main.async {
            PluginManager.shared.showPluginNotification(title: title, message: message, style: .info, pluginId: self.pluginId)
        }
    }

    func executeAction(identifier: String, parameters: ActionParameters) throws {
        try PluginManager.shared.executeAction(identifier: identifier, parameters: parameters)
    }
}

/// Tracks loaded plugins that adopt `PluginExtension`: attaches hosts, runs their
/// services, and routes settings changes. Main-thread only (calls hop if needed).
final class PluginExtensionManager: ObservableObject {
    static let shared = PluginExtensionManager()

    private struct Entry {
        let id: String
        let name: String
        let ext: PluginExtension
        let host: PluginHostImpl
        var serviceRunning = false
    }
    private var entries: [String: Entry] = [:]
    /// Bumped on every change so SwiftUI views refresh.
    @Published private(set) var revision = 0
    /// Bumped only when a plugin is registered or removed (Settings rebuilds its plugin tabs on this).
    @Published private(set) var registrationCount = 0

    private func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    func register(_ instance: AnyObject, identifier: String, name: String) {
        onMain {
            guard let ext = instance as? PluginExtension else { return }
            unregister(identifier: identifier)
            let host = PluginHostImpl(pluginId: identifier, name: name)
            host.manager = self; host.ext = ext
            entries[identifier] = Entry(id: identifier, name: name, ext: ext, host: host)
            ext.pluginAttached(host: host)
            if ext.runsBackgroundService, serviceEnabled(identifier) { startService(identifier) }
            revision += 1
            registrationCount += 1
        }
    }

    func unregister(identifier: String) {
        onMain {
            guard let e = entries[identifier] else { return }
            if e.serviceRunning { e.ext.stopService() }
            e.ext.pluginDetached()
            entries[identifier] = nil
            revision += 1
            registrationCount += 1
        }
    }

    // MARK: queries (for UI)

    /// Every loaded plugin (built in or installed from a library) that offers options, by name.
    func pluginsWithSettings() -> [(id: String, name: String)] {
        onMain {
            entries.values
                .filter { !$0.ext.settingsFields.isEmpty || $0.ext.hasCustomSettingsView || $0.ext.runsBackgroundService }
                .map { ($0.id, $0.name) }
                .sorted { $0.1 < $1.1 }
        }
    }

    func hasSettingsUI(_ id: String) -> Bool {
        onMain {
            guard let e = entries[id] else { return false }
            return !e.ext.settingsFields.isEmpty || e.ext.runsBackgroundService || e.ext.hasCustomSettingsView
        }
    }
    func fields(_ id: String) -> [PluginSettingField] { onMain { entries[id]?.ext.settingsFields ?? [] } }
    func runsService(_ id: String) -> Bool { onMain { entries[id]?.ext.runsBackgroundService ?? false } }
    func isServiceRunning(_ id: String) -> Bool { onMain { entries[id]?.serviceRunning ?? false } }
    func makeCustomView(_ id: String) -> NSView? { onMain { entries[id]?.ext.makeSettingsView() } }
    func value(_ id: String, _ key: String) -> Any? { onMain { entries[id]?.host.setting(key) } }

    func serviceEnabled(_ id: String) -> Bool {
        (PluginSettingsStore.shared.value(id, PluginSettingsStore.serviceEnabledKey) as? Bool) ?? true
    }

    // MARK: mutations

    func setSetting(_ id: String, _ key: String, _ value: Any?) {
        onMain {
            PluginSettingsStore.shared.set(id, key, value)
            if let e = entries[id] {
                e.ext.settingChanged(key: key, value: e.host.setting(key))
            }
            revision += 1
        }
    }

    func setServiceEnabled(_ id: String, _ on: Bool) {
        onMain {
            PluginSettingsStore.shared.set(id, PluginSettingsStore.serviceEnabledKey, on)
            if on { startService(id) } else { stopService(id) }
            revision += 1
        }
    }

    private func startService(_ id: String) {
        guard var e = entries[id], !e.serviceRunning else { return }
        do {
            try e.ext.startService()
            e.serviceRunning = true
            entries[id] = e
            log.log("Plugin service started: \(id)")
        } catch {
            log.log("Plugin service failed to start (\(id)): \(error)")
        }
    }

    private func stopService(_ id: String) {
        guard var e = entries[id], e.serviceRunning else { return }
        e.ext.stopService()
        e.serviceRunning = false
        entries[id] = e
        log.log("Plugin service stopped: \(id)")
    }
}
