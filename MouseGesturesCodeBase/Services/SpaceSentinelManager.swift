import Cocoa
import ApplicationServices

/// Enables instant, modifier-independent switching to any desktop Space the
/// user has visited during this session, by keeping one hidden window of our
/// own on each Space and "focusing" it directly via private WindowServer APIs
/// — the same mechanism third-party window switchers (e.g. AltTab) use to
/// bring a window on another Space to the front.
///
/// Why this exists: the previous approach (Ctrl+Left/Right key simulation)
/// is the only mechanism found that performs a genuine, Dock-coordinated,
/// animated Space switch — but it requires physically-held modifier keys to
/// be released first (`waitForModifierRelease()`, up to 1.5s), because a
/// physically-held modifier gets OR'd into the synthesized event and changes
/// which shortcut fires. A private direct switch
/// (`SLSManagedDisplaySetCurrentSpace`) was also tried and reverted: it moves
/// the WindowServer's logical active Space but the Dock never learns about it
/// and doesn't animate, leaving a broken hybrid state (both menu bars
/// visible, and the next switch acting on the space the Dock still thinks is
/// active).
///
/// This mechanism sidesteps both problems: it posts no keyboard events at
/// all, so held modifiers are irrelevant, and it drives the *same* frontmost/
/// key-window path a real user click does, so the Dock's own Space tracking
/// stays in sync and the transition animates normally.
///
/// Verified live on macOS 26.5 (Tahoe): sentinel windows created on 3
/// different Spaces, then focused in arbitrary (non-adjacent) order — each
/// jump landed on the correct Space, confirmed via `SLSGetActiveSpace`
/// read-back, with a normal Ctrl+arrow switch immediately afterward
/// proceeding correctly (i.e. no hybrid-state divergence).
final class SpaceSentinelManager {
    static let shared = SpaceSentinelManager()

    private struct Sentinel {
        let window: NSWindow
        let axElement: AXUIElement
        let windowID: CGWindowID
    }

    /// One hidden sentinel window per Space ID the user has visited since launch.
    /// Guarded by `sentinelsLock`: it is WRITTEN on the main thread (from the
    /// activeSpaceDidChange observer, which is registered with `queue: .main`,
    /// and the launch dispatch), but READ and PRUNED on a background queue —
    /// action execution runs `switchToSpace(...)` off the main thread (see
    /// ActionExecutionManager, which dispatches plugin execution to
    /// `DispatchQueue.global(qos: .userInitiated)`). Unsynchronized `Dictionary`
    /// access from two threads is a data race that can corrupt the heap during a
    /// copy-on-write resize, so every access below takes the lock.
    private var sentinels: [UInt64: Sentinel] = [:]
    private let sentinelsLock = NSLock()
    private var observer: NSObjectProtocol?
    private let myPid = ProcessInfo.processInfo.processIdentifier

    // MARK: - Private WindowServer API bridging

    private typealias MainConnectionIDFn = @convention(c) () -> UInt32
    private typealias GetActiveSpaceFn = @convention(c) (UInt32) -> UInt64
    private typealias CopyDisplayForSpaceFn = @convention(c) (UInt32, UInt64) -> CFString?
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (UInt32) -> CFArray?
    private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    private typealias SetFrontProcessFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32) -> Int32
    private typealias PostEventRecordFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32
    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32

    private static func load<T>(_ name: String, from path: String) -> T? {
        guard let sym = dlsym(dlopen(path, RTLD_LAZY), name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let coreGraphicsPath = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    private static let hiServicesPath = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/HIServices"

    private static let mainConnectionID: MainConnectionIDFn? = load("SLSMainConnectionID", from: skyLightPath)
    private static let getActiveSpaceFn: GetActiveSpaceFn? = load("SLSGetActiveSpace", from: skyLightPath)
    private static let copyDisplayForSpace: CopyDisplayForSpaceFn? = load("SLSCopyManagedDisplayForSpace", from: skyLightPath)
    private static let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn? = load("SLSCopyManagedDisplaySpaces", from: skyLightPath)
    private static let postEventRecordTo: PostEventRecordFn? = load("SLPSPostEventRecordTo", from: skyLightPath)
    private static let setFrontProcessWithOptions: SetFrontProcessFn? = load("CPSSetFrontProcessWithOptions", from: coreGraphicsPath)
    private static let getProcessForPID: GetProcessForPIDFn? = load("GetProcessForPID", from: hiServicesPath)
    private static let axGetWindow: AXGetWindowFn? = load("_AXUIElementGetWindow", from: hiServicesPath)

    /// SLPSMode.userGenerated — the mode alt-tab-macos uses for cross-Space focus.
    private static let userGeneratedMode: UInt32 = 0x200

    private init() {
        // NSWorkspaceActiveSpaceDidChangeNotification is only delivered via
        // NSWorkspace's OWN notification center, not NotificationCenter.default
        // (confirmed against the NSWorkspace.h doc comment: "All notifications
        // in this header file must be registered on this notification center.
        // If you register on other notification centers, you will not receive
        // the notifications.") Registering on .default silently never fires.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            self?.ensureSentinelOnCurrentSpace()
        }
        // Claim a sentinel on the Space we're launched into.
        DispatchQueue.main.async { [weak self] in self?.ensureSentinelOnCurrentSpace() }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    // MARK: - Space enumeration (read-only, unauthenticated SkyLight calls)

    /// Returns the currently active Space ID, or nil if the private API is unavailable.
    func currentSpaceID() -> UInt64? {
        guard let mainConnectionID = Self.mainConnectionID, let getActiveSpaceFn = Self.getActiveSpaceFn else { return nil }
        return getActiveSpaceFn(mainConnectionID())
    }

    /// Returns the ordered list of Space IDs on the display currently hosting
    /// the active Space, or an empty array if unavailable.
    func orderedSpaceIDs() -> [UInt64] {
        guard let mainConnectionID = Self.mainConnectionID,
              let getActiveSpaceFn = Self.getActiveSpaceFn,
              let copyDisplayForSpace = Self.copyDisplayForSpace,
              let copyManagedDisplaySpaces = Self.copyManagedDisplaySpaces else { return [] }

        let cid = mainConnectionID()
        let active = getActiveSpaceFn(cid)
        guard let displayUUID = copyDisplayForSpace(cid, active),
              let displaySpaces = copyManagedDisplaySpaces(cid) else { return [] }

        var spaceIDs: [UInt64] = []
        for i in 0..<CFArrayGetCount(displaySpaces) {
            guard let raw = CFArrayGetValueAtIndex(displaySpaces, i) else { continue }
            let dict = Unmanaged<NSDictionary>.fromOpaque(raw).takeUnretainedValue()
            guard (dict["Display Identifier"] as? String) == (displayUUID as String),
                  let spaces = dict["Spaces"] as? [NSDictionary] else { continue }
            for space in spaces {
                if let id64 = space["id64"] as? NSNumber { spaceIDs.append(id64.uint64Value) }
            }
        }
        return spaceIDs
    }

    // MARK: - Sentinel lifecycle

    private func ensureSentinelOnCurrentSpace() {
        guard let spaceID = currentSpaceID() else {
            log.log("SpaceSentinel: no currentSpaceID (private API unavailable)", file: #file, function: #function, line: #line)
            return
        }
        sentinelsLock.lock()
        let alreadyHave = sentinels[spaceID] != nil
        sentinelsLock.unlock()
        guard !alreadyHave else { return }

        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 4, height: 4),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.alphaValue = 0
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.level = .normal
        window.orderFront(nil)

        // Resolve the AXUIElement for this window via our own process's AX tree
        // so it can be raised with kAXRaiseAction after the front-process call.
        guard let axGetWindow = Self.axGetWindow else { window.orderOut(nil); return }
        let axApp = AXUIElementCreateApplication(myPid)
        var windowsValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
        guard let axWindows = windowsValue as? [AXUIElement] else { window.orderOut(nil); return }

        let targetWid = CGWindowID(window.windowNumber)
        guard let axElement = axWindows.first(where: { element in
            var wid: CGWindowID = 0
            _ = axGetWindow(element, &wid)
            return wid == targetWid
        }) else {
            log.log("SpaceSentinel: could not resolve AX element for sentinel window on space \(spaceID)", file: #file, function: #function, line: #line)
            window.orderOut(nil)
            return
        }
        log.log("SpaceSentinel: sentinel ready for space \(spaceID)", file: #file, function: #function, line: #line)

        sentinelsLock.lock()
        sentinels[spaceID] = Sentinel(window: window, axElement: axElement, windowID: targetWid)
        sentinelsLock.unlock()
    }

    /// Drops the sentinel for Space IDs that are no longer present on any
    /// display (the user closed/merged that Space). Call this periodically
    /// (e.g. from `ensureSentinelOnCurrentSpace`'s notification) to avoid
    /// leaking hidden windows for Spaces that no longer exist. Currently
    /// invoked lazily; a stale sentinel is harmless (its focus call simply
    /// fails and the caller falls back to key simulation) so this is a
    /// housekeeping nicety, not a correctness requirement.
    private func pruneStaleSentinels(validSpaceIDs: Set<UInt64>) {
        sentinelsLock.lock()
        let stale = sentinels.filter { !validSpaceIDs.contains($0.key) }
        for key in stale.keys { sentinels.removeValue(forKey: key) }
        sentinelsLock.unlock()

        guard !stale.isEmpty else { return }
        // `orderOut` is an AppKit call and must run on the main thread; prune is
        // reachable from the background action-execution queue (via
        // `switchToSpace`), so marshal the window teardown to main. The captured
        // windows stay retained by the closure until it runs, so there's no
        // use-after-free even though they've already left the dictionary.
        let windows = stale.values.map { $0.window }
        let hide = { windows.forEach { $0.orderOut(nil) } }
        if Thread.isMainThread { hide() } else { DispatchQueue.main.async(execute: hide) }
    }

    // MARK: - Focus (the actual switch)

    /// Synthesizes the same activation sequence a real click on a window
    /// living on another Space produces: bring its process forward, deliver a
    /// synthetic left-mouse-down/up pair directly to that window (so it
    /// becomes key), then raise it via Accessibility. WindowServer follows
    /// the window to its Space and plays the normal transition animation.
    private func focus(_ sentinel: Sentinel) -> Bool {
        guard let getProcessForPID = Self.getProcessForPID,
              let setFrontProcessWithOptions = Self.setFrontProcessWithOptions,
              let postEventRecordTo = Self.postEventRecordTo else { return false }

        var psn = ProcessSerialNumber()
        guard getProcessForPID(myPid, &psn) == 0 else { return false }
        guard setFrontProcessWithOptions(&psn, Self.userGeneratedMode) == 0 else { return false }

        makeKeyWindow(&psn, sentinel.windowID, postEventRecordTo: postEventRecordTo)

        // AXUIElementPerformAction on our own window must run on the main
        // thread — calling it from a background thread deadlocks (confirmed
        // live: the call never returns).
        if Thread.isMainThread {
            _ = AXUIElementPerformAction(sentinel.axElement, kAXRaiseAction as CFString)
        } else {
            DispatchQueue.main.async {
                _ = AXUIElementPerformAction(sentinel.axElement, kAXRaiseAction as CFString)
            }
        }
        return true
    }

    /// Posts a synthetic left-mouse-down/up pair addressed directly to
    /// `wid` (by window ID, not screen coordinates — the click point is
    /// placed just outside the window's content so it hit-tests to no view),
    /// which the target app's process reads as "you are now the key window."
    /// Byte layout matches the private `SLPSPostEventRecordTo` event record
    /// used by AltTab-style window switchers.
    private func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID, postEventRecordTo: PostEventRecordFn) {
        var wid = wid
        var offContentPoint = CGPoint(x: -1, y: -1)
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        memcpy(&bytes[0x3c], &wid, MemoryLayout<CGWindowID>.size)
        memcpy(&bytes[0x20], &offContentPoint, MemoryLayout<CGPoint>.size)
        bytes[0x08] = 0x01 // left-mouse-down
        _ = postEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02 // left-mouse-up
        _ = postEventRecordTo(&psn, &bytes)
    }

    // MARK: - Public switching API

    /// Attempts to switch directly to `spaceID`. Returns false (caller should
    /// fall back to key simulation) if no sentinel has been placed there yet
    /// (the user hasn't visited it this session) or the private API is
    /// unavailable.
    @discardableResult
    func switchToSpace(_ spaceID: UInt64) -> Bool {
        sentinelsLock.lock()
        let sentinel = sentinels[spaceID]
        sentinelsLock.unlock()
        guard let sentinel else { return false }
        pruneStaleSentinels(validSpaceIDs: Set(orderedSpaceIDs()))
        return focus(sentinel)
    }

    /// Switches to the next/previous Space in display order, wrapping around.
    /// Returns false if the adjacent Space hasn't been visited yet (no
    /// sentinel) or there's only one Space.
    @discardableResult
    func switchToAdjacentSpace(next: Bool) -> Bool {
        let ids = orderedSpaceIDs()
        guard ids.count > 1, let active = currentSpaceID(),
              let currentIndex = ids.firstIndex(of: active) else { return false }
        let targetIndex = next
            ? (currentIndex + 1) % ids.count
            : (currentIndex - 1 + ids.count) % ids.count
        return switchToSpace(ids[targetIndex])
    }

    /// Switches to the Space at 1-indexed display position `number` (as the
    /// user would see them in Mission Control), if it's been visited.
    @discardableResult
    func switchToSpace(atPosition number: Int) -> Bool {
        let ids = orderedSpaceIDs()
        guard number >= 1, number <= ids.count else { return false }
        return switchToSpace(ids[number - 1])
    }
}
