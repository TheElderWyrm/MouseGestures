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
///
/// # Keeping the sentinels out of Mission Control
///
/// A sentinel is a real, WindowServer-managed window, so by default Mission
/// Control lays out a tile for it — an empty 4x4 ghost on every Space. That
/// was user-visible and is what `missionControlHiddenBehavior` below fixes.
///
/// Everything in the next paragraph was established empirically with
/// standalone `swiftc` probes (this project's established technique), not from
/// documentation. The measurement: while Mission Control is up, the Dock
/// exposes one `AXButton` per window it is displaying under
/// `Dock > AXGroup "Mission Control" > <per-display group> > <windows group>`;
/// counting those buttons with and without a sentinel is an exact, screenshot-
/// free measure of the pollution. Space membership was read back with
/// `SLSCopySpacesForWindows`, and every candidate was put through real
/// desktop-to-desktop jumps driven only by `focus(_:)`.
///
/// Results (baseline = 10 Mission Control tiles, shipped config adds 1):
///   * `level = .floating`                     -> 0 extra tiles, but **0/4 jumps**
///   * `collectionBehavior = .stationary`      -> 0 extra tiles, but **0/4 jumps**
///   * `collectionBehavior = .transient`       -> 0 extra tiles, but **0/3 jumps**
///   * `NSPanel(.nonactivatingPanel)`          -> jumps fine (4/4), but still 1 extra tile
///   * `.canJoinAllSpaces`                     -> reported TWO Space IDs, i.e. it
///     destroys the per-Space identity the whole design rests on
///
/// So the property that makes WindowServer follow a window to its Space is the
/// *same* property that puts it in Mission Control: being a managed window.
/// There is no static configuration that has one without the other.
///
/// The fix is therefore temporal, not static: the sentinel sits `.stationary`
/// (invisible to Mission Control / Exposé) at rest, and `focus(_:)` clears the
/// flag for the instant of the switch, restoring it afterwards. Measured:
/// 10/10 desktop-to-desktop jumps, each landing in 0.41s — bit-for-bit the same
/// latency as the shipped `.normal`/default config — with 0 extra Mission
/// Control tiles both before and after the jumps, and both sentinels still
/// reporting exactly one (unchanged) Space ID afterwards. Clearing the flag
/// needs no settling delay: the write reaches the WindowServer before the very
/// next line runs.
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

    /// Resting state: `.stationary` is what actually keeps the sentinel out of
    /// Mission Control / Exposé (proved by A/B-ing the Dock's own Mission
    /// Control window list — see the type comment). `.ignoresCycle` additionally
    /// keeps it out of Cmd-` window cycling. Both are cleared for the duration
    /// of a switch, because `.stationary` also stops WindowServer from following
    /// the window to its Space.
    private static let missionControlHiddenBehavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]

    /// The collection behavior the sentinel must be wearing at the moment of a
    /// switch. Empty == `NSWindow`'s own default, i.e. exactly the configuration
    /// the original mechanism was verified against.
    private static let switchableBehavior: NSWindow.CollectionBehavior = []

    /// How long after a switch is kicked off the sentinel goes back into hiding.
    /// Comfortably longer than the observed 0.41s land time so the re-hide can
    /// never race the transition it belongs to.
    private static let rehideDelay: TimeInterval = 1.5

    /// Per-sentinel re-hide tokens, so two switches in quick succession can't
    /// have the first one's timer re-hide a sentinel the second one just
    /// un-hid. Main-thread only (written and read solely from `focus`'s
    /// main-thread block and the timer it schedules).
    private var rehideTokens: [CGWindowID: Int] = [:]

    // MARK: - Private WindowServer API bridging

    private typealias MainConnectionIDFn = @convention(c) () -> UInt32
    private typealias GetActiveSpaceFn = @convention(c) (UInt32) -> UInt64
    private typealias CopyDisplayForSpaceFn = @convention(c) (UInt32, UInt64) -> CFString?
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (UInt32) -> CFArray?
    private typealias CopySpacesForWindowsFn = @convention(c) (UInt32, UInt32, CFArray) -> CFArray?
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
    private static let copySpacesForWindows: CopySpacesForWindowsFn? = load("SLSCopySpacesForWindows", from: skyLightPath)
    private static let postEventRecordTo: PostEventRecordFn? = load("SLPSPostEventRecordTo", from: skyLightPath)
    private static let setFrontProcessWithOptions: SetFrontProcessFn? = load("CPSSetFrontProcessWithOptions", from: coreGraphicsPath)
    private static let getProcessForPID: GetProcessForPIDFn? = load("GetProcessForPID", from: hiServicesPath)
    private static let axGetWindow: AXGetWindowFn? = load("_AXUIElementGetWindow", from: hiServicesPath)

    /// SLPSMode.userGenerated — the mode alt-tab-macos uses for cross-Space focus.
    private static let userGeneratedMode: UInt32 = 0x200

    /// `kCGSAllSpacesMask` — current | others | user, i.e. "tell me every Space
    /// this window belongs to."
    private static let allSpacesMask: UInt32 = 0x7

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

    /// Every Space ID that currently exists, across *all* displays.
    ///
    /// `orderedSpaceIDs()` deliberately covers only the display hosting the
    /// active Space (it exists to mirror Mission Control's visual ordering for
    /// "switch to Space N"), so it is the wrong input for deciding which
    /// sentinels are stale — on a multi-display setup it would condemn every
    /// sentinel living on another monitor. Returns an empty set if the private
    /// API is unavailable, and callers treat that as "prune nothing."
    private func allSpaceIDs() -> Set<UInt64> {
        guard let mainConnectionID = Self.mainConnectionID,
              let copyManagedDisplaySpaces = Self.copyManagedDisplaySpaces,
              let displaySpaces = copyManagedDisplaySpaces(mainConnectionID()) else { return [] }

        var ids: Set<UInt64> = []
        for i in 0..<CFArrayGetCount(displaySpaces) {
            guard let raw = CFArrayGetValueAtIndex(displaySpaces, i) else { continue }
            let dict = Unmanaged<NSDictionary>.fromOpaque(raw).takeUnretainedValue()
            guard let spaces = dict["Spaces"] as? [NSDictionary] else { continue }
            for space in spaces {
                if let id64 = space["id64"] as? NSNumber { ids.insert(id64.uint64Value) }
            }
        }
        return ids
    }

    /// The Space IDs a sentinel window actually belongs to right now, straight
    /// from the WindowServer. Empty means "don't know" (private API missing, or
    /// the window hasn't been committed yet) and must never be read as "belongs
    /// to no Space" — callers degrade to trusting their bookkeeping.
    private func spaceIDs(ofWindow windowID: CGWindowID) -> [UInt64] {
        guard let mainConnectionID = Self.mainConnectionID,
              let copySpacesForWindows = Self.copySpacesForWindows,
              let result = copySpacesForWindows(mainConnectionID(), Self.allSpacesMask, [windowID] as CFArray)
        else { return [] }
        return (result as? [NSNumber])?.map { $0.uint64Value } ?? []
    }

    // MARK: - Sentinel lifecycle

    private func ensureSentinelOnCurrentSpace() {
        // Collect sentinels for Spaces that no longer exist. This has to happen
        // on every Space change, not just when a switch action runs: macOS mints
        // a brand-new Space ID every time any app enters full screen and destroys
        // it on exit, so a session that never fires a switch gesture would
        // otherwise accumulate one orphaned hidden window per full-screen
        // transition (nine were observed live on one machine, six of them
        // stranded on a full-screen Space that no longer existed).
        pruneStaleSentinels(validSpaceIDs: allSpaceIDs())

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
        // Level MUST stay `.normal`: raising it to `.floating` was measured to
        // hide the sentinel from Mission Control but also to break the switch
        // outright (0/4 jumps). Only a window WindowServer considers managed
        // gets followed to its Space.
        window.level = .normal
        window.collectionBehavior = Self.missionControlHiddenBehavior
        window.isExcludedFromWindowsMenu = true
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
    /// display (the user closed/merged that Space, or a full-screen Space was
    /// torn down). Called on every Space change and before every switch.
    ///
    /// A stale sentinel is not merely untidy: when its Space is destroyed the
    /// WindowServer re-homes the window onto some surviving Space, so the entry
    /// now points at a window that lives somewhere else entirely and "switch to
    /// that Space" would land on the wrong one. Passing an empty
    /// `validSpaceIDs` (private API unavailable) prunes nothing, deliberately.
    private func pruneStaleSentinels(validSpaceIDs: Set<UInt64>) {
        guard !validSpaceIDs.isEmpty else { return }
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

        // Resolve our PSN up front — a thread-agnostic process-table lookup; a
        // failure means we can't switch, so signal the caller to fall back to key
        // simulation.
        var resolved = ProcessSerialNumber()
        guard getProcessForPID(myPid, &resolved) == 0 else { return false }
        let psn = resolved

        // Run the ENTIRE activation — bring-process-forward, synthetic key-click,
        // and AX raise — on the main thread as one unit. The AX raise must be on
        // main (off-main it deadlocks — confirmed live), and AltTab (the reference
        // implementation this sequence is derived from) performs the whole sequence
        // on main. Keeping it together on one thread also removes the previous
        // split's ordering hazard, where the background front-process/synthetic
        // click and the async main-thread raise could interleave across two quick
        // consecutive switches.
        let perform = { [self] in
            // Re-admit the sentinel to the set of windows WindowServer manages,
            // for the duration of this switch only. At rest it wears
            // `.stationary` so Mission Control ignores it, but `.stationary`
            // also stops WindowServer from following it to its Space — measured,
            // not assumed (see the type comment). The write lands before the
            // next line: 10/10 probe jumps succeeded with no settling delay.
            sentinel.window.collectionBehavior = Self.switchableBehavior

            var psn = psn
            guard setFrontProcessWithOptions(&psn, Self.userGeneratedMode) == 0 else {
                rehide(sentinel, after: 0)
                return
            }
            makeKeyWindow(&psn, sentinel.windowID, postEventRecordTo: postEventRecordTo)
            _ = AXUIElementPerformAction(sentinel.axElement, kAXRaiseAction as CFString)
            rehide(sentinel, after: Self.rehideDelay)
        }
        if Thread.isMainThread { perform() } else { DispatchQueue.main.async(execute: perform) }
        return true
    }

    /// Puts a sentinel back into its Mission-Control-invisible resting state once
    /// the transition it was un-hidden for has finished. Main thread only.
    /// The token guards against a stale timer from an earlier switch re-hiding a
    /// sentinel that a newer switch has just deliberately un-hidden.
    private func rehide(_ sentinel: Sentinel, after delay: TimeInterval) {
        let id = sentinel.windowID
        let token = (rehideTokens[id] ?? 0) + 1
        rehideTokens[id] = token
        let apply = { [weak self, weak window = sentinel.window] in
            guard let self, let window, self.rehideTokens[id] == token else { return }
            window.collectionBehavior = Self.missionControlHiddenBehavior
            self.rehideTokens[id] = nil
        }
        if delay <= 0 { apply() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: apply) }
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
    /// (the user hasn't visited it this session), if the sentinel we have has
    /// drifted off that Space, or if the private API is unavailable.
    @discardableResult
    func switchToSpace(_ spaceID: UInt64) -> Bool {
        pruneStaleSentinels(validSpaceIDs: allSpaceIDs())

        sentinelsLock.lock()
        let sentinel = sentinels[spaceID]
        sentinelsLock.unlock()
        guard let sentinel else { return false }

        // Confirm with the WindowServer that the sentinel is still on the Space
        // we filed it under. A window whose Space was destroyed gets re-homed
        // elsewhere, and focusing it would then quietly switch to the WRONG
        // Space — worse than not switching, since the caller's key-simulation
        // fallback would have got it right. An empty answer means "unavailable",
        // not "nowhere", so it is not treated as a mismatch.
        let actual = spaceIDs(ofWindow: sentinel.windowID)
        if !actual.isEmpty && !actual.contains(spaceID) {
            log.log("SpaceSentinel: sentinel for space \(spaceID) has drifted to \(actual); dropping it", file: #file, function: #function, line: #line)
            sentinelsLock.lock()
            let dropped = sentinels.removeValue(forKey: spaceID)
            sentinelsLock.unlock()
            if let dropped {
                let hide = { dropped.window.orderOut(nil) }
                if Thread.isMainThread { hide() } else { DispatchQueue.main.async(execute: hide) }
            }
            return false
        }

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
