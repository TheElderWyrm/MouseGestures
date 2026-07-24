import Foundation

/// Dev hook: lets a developer script MouseGestures from the shell without
/// configuring a gesture or clicking through the UI, two ways:
///
/// 1. **At launch** — `--run-action <identifier> [key=value,...]` arguments,
///    or the `MG_RUN_ACTION`/`MG_RUN_ACTION_PARAMS` environment variables
///    (handy with `open -a`/launchd where argv isn't easy to pass through).
///    Prints `MG_ACTION_RESULT: ok` / `MG_ACTION_RESULT: error <description>`
///    to stdout and exits, unless `--run-action-keep-running` is also passed.
///
/// 2. **Against an already-running instance** — post a
///    `com.mousegestures.devRunAction` Darwin distributed notification (works
///    across process boundaries, no IPC setup needed) with `identifier` and
///    optional `parameters` in the userInfo. From the shell:
///    `osascript -e 'tell app "System Events" to «event MGrRunA» given «class idnt»:"com.mousegestures.window.cycle_space", «class parm»:"direction=next"'`
///    is unwieldy from AppleScript, so prefer a tiny compiled helper that
///    calls `DistributedNotificationCenter.default().postNotificationName`,
///    or just relaunch the app with `--run-action` for a one-shot test — that
///    covers the common case since sentinel/plugin state rebuilds fast.
///
/// This exists because most of this app's action surface (private WindowServer
/// calls, animated Space switches, hidden sentinel windows, etc.) can't be
/// meaningfully verified by unit tests or by reading the code — it has to be
/// exercised live. Scripting it from the shell is far more reliable than
/// driving the SwiftUI settings UI via Accessibility automation.
enum DevActionRunnerHook {
    static let distributedNotificationName = Notification.Name("com.mousegestures.devRunAction")

    /// Call once from `applicationDidFinishLaunching`, after plugins have
    /// loaded. Registers the distributed-notification listener (always, so a
    /// running instance can be scripted later) and, if a run request is
    /// already present via argv/env, executes it once at startup.
    static func runIfRequested() {
        DistributedNotificationCenter.default().addObserver(
            forName: distributedNotificationName, object: nil, queue: .main
        ) { notification in
            guard let identifier = notification.userInfo?["identifier"] as? String else { return }
            let paramsText = notification.userInfo?["parameters"] as? String ?? ""
            execute(identifier: identifier, paramsText: paramsText, exitAfter: false)
        }

        guard let (identifier, paramsText) = requestedAction() else { return }
        let keepRunning = CommandLine.arguments.contains("--run-action-keep-running")
        // Give plugin loading / detection setup a moment to settle before
        // executing, matching how a real gesture would fire well after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            execute(identifier: identifier, paramsText: paramsText, exitAfter: !keepRunning)
        }
    }

    private static func execute(identifier: String, paramsText: String, exitAfter: Bool) {
        let parameters = ActionParameters.parse(commaSeparated: paramsText)
        do {
            try PluginManager.shared.executeAction(identifier: identifier, parameters: parameters)
            print("MG_ACTION_RESULT: ok")
        } catch {
            print("MG_ACTION_RESULT: error \(error.localizedDescription)")
        }
        if exitAfter { exit(0) }
    }

    /// Reads the requested action identifier + parameter text from either
    /// `--run-action <identifier> [key=value,...]` command-line arguments or
    /// the `MG_RUN_ACTION` / `MG_RUN_ACTION_PARAMS` environment variables.
    private static func requestedAction() -> (identifier: String, parameters: String)? {
        let args = CommandLine.arguments
        if let flagIndex = args.firstIndex(of: "--run-action"), args.count > flagIndex + 1 {
            let identifier = args[flagIndex + 1]
            let parameters = args.count > flagIndex + 2 ? args[flagIndex + 2] : ""
            return (identifier, parameters)
        }
        if let identifier = ProcessInfo.processInfo.environment["MG_RUN_ACTION"] {
            let parameters = ProcessInfo.processInfo.environment["MG_RUN_ACTION_PARAMS"] ?? ""
            return (identifier, parameters)
        }
        return nil
    }
}
