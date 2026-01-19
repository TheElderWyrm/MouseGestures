import Cocoa
import Carbon

// Window targeting system for advanced window selection
class WindowTargeting {
    static let shared = WindowTargeting()
    
    private init() {}
    
    // MARK: - Window Target Types
    enum TargetType: String, Codable, CaseIterable {
        case frontmost = "Frontmost Window"
        case byAge = "Window by Age (nth most recent)"
        case byApplication = "Specific Application"
        case byWindowTitle = "Window by Title"
        case byWindowTitleContains = "Window Title Contains"
        case allWindowsOfApp = "All Windows of Application"
        case allWindows = "All Windows"
        case mousePosition = "Window Under Mouse"
        case largestWindow = "Largest Window"
        case smallestWindow = "Smallest Window"
    }
    
    // MARK: - Window Target Configuration
    struct WindowTarget: Codable, Equatable {
        var targetType: TargetType
        var applicationBundleId: String? // For byApplication
        var applicationName: String? // Display name for UI
        var windowTitle: String? // For byWindowTitle
        var windowTitleContains: String? // For byWindowTitleContains
        var windowAge: Int? // For byAge (1 = frontmost, 2 = second frontmost, etc.)
        
        init(targetType: TargetType = .frontmost) {
            self.targetType = targetType
        }
        
        var displayString: String {
            switch targetType {
            case .frontmost:
                return "Frontmost Window"
            case .byAge:
                if let age = windowAge {
                    switch age {
                    case 1: return "Frontmost Window"
                    case 2: return "Second Frontmost Window"
                    case 3: return "Third Frontmost Window"
                    default: return "\(age)th Most Recent Window"
                    }
                }
                return "Window by Age"
            case .byApplication:
                return applicationName ?? applicationBundleId ?? "Specific Application"
            case .byWindowTitle:
                return "Window: \(windowTitle ?? "No Title")"
            case .byWindowTitleContains:
                return "Window containing: \(windowTitleContains ?? "No Pattern")"
            case .allWindowsOfApp:
                return "All windows of \(applicationName ?? applicationBundleId ?? "App")"
            case .allWindows:
                return "All Windows"
            case .mousePosition:
                return "Window Under Mouse"
            case .largestWindow:
                return "Largest Window"
            case .smallestWindow:
                return "Smallest Window"
            }
        }
    }
    
    // MARK: - Window Information
    struct WindowInfo {
        let window: AXUIElement
        let pid: pid_t
        let application: NSRunningApplication?
        let title: String?
        let frame: CGRect?
        let creationTime: Date? // Approximated by window order
        let orderIndex: Int // Position in window list (0 = frontmost)
        
        var size: CGFloat? {
            guard let frame = frame else { return nil }
            return frame.width * frame.height
        }
    }
    
    // MARK: - Main Targeting Methods
    
    static func getTargetWindow(_ target: WindowTarget) -> (AXUIElement, pid_t)? {
        switch target.targetType {
        case .frontmost:
            return getFrontmostWindow()
            
        case .byAge:
            let age = target.windowAge ?? 1
            return getWindowByAge(age)
            
        case .byApplication:
            guard let bundleId = target.applicationBundleId else { return nil }
            return getWindowForApplication(bundleId: bundleId)
            
        case .byWindowTitle:
            guard let title = target.windowTitle else { return nil }
            return getWindowByTitle(title)
            
        case .byWindowTitleContains:
            guard let pattern = target.windowTitleContains else { return nil }
            return getWindowByTitleContains(pattern)
            
        case .allWindowsOfApp:
            // This returns multiple windows, handled separately
            return nil
            
        case .allWindows:
            // This returns multiple windows, handled separately
            return nil
            
        case .mousePosition:
            return getWindowUnderMouse()
            
        case .largestWindow:
            return getLargestWindow()
            
        case .smallestWindow:
            return getSmallestWindow()
        }
    }
    
    static func getTargetWindows(_ target: WindowTarget) -> [(AXUIElement, pid_t)] {
        switch target.targetType {
        case .allWindowsOfApp:
            guard let bundleId = target.applicationBundleId else { return [] }
            return getAllWindowsForApplication(bundleId: bundleId)
        case .allWindows:
            return getAllWindows()
        default:
            if let window = getTargetWindow(target) {
                return [window]
            }
            return []
        }
    }
    
    // MARK: - Window Discovery Methods
    
    private static func getFrontmostWindow() -> (AXUIElement, pid_t)? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            log.log("No frontmost application found")
            return nil
        }
        
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windowValue: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        
        if result == .success, let window = windowValue {
            return (window as! AXUIElement, pid)
        }
        
        return nil
    }
    
    private static func getWindowByAge(_ age: Int) -> (AXUIElement, pid_t)? {
        guard age > 0 else { return nil }
        
        let allWindows = getAllVisibleWindows()
        
        // Sort by most recent (approximated by window order)
        let sortedWindows = allWindows.sorted { $0.orderIndex < $1.orderIndex }
        
        guard sortedWindows.count >= age else {
            log.log("Not enough windows. Requested: \(age), Available: \(sortedWindows.count)")
            return nil
        }
        
        let targetWindow = sortedWindows[age - 1]
        return (targetWindow.window, targetWindow.pid)
    }
    
    private static func getWindowForApplication(bundleId: String) -> (AXUIElement, pid_t)? {
        // Find the application
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
        
        guard let app = apps.first else {
            log.log("Application not found: \(bundleId)")
            return nil
        }
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Try to get focused window first
        var windowValue: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        
        if result == .success, let window = windowValue {
            return (window as! AXUIElement, pid)
        }
        
        // If no focused window, try to get first window
        var windowsValue: CFTypeRef?
        result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        
        if result == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty {
            return (windows[0], pid)
        }
        
        return nil
    }
    
    private static func getWindowByTitle(_ title: String) -> (AXUIElement, pid_t)? {
        let allWindows = getAllVisibleWindows()
        
        for windowInfo in allWindows {
            if windowInfo.title == title {
                return (windowInfo.window, windowInfo.pid)
            }
        }
        
        log.log("No window found with title: \(title)")
        return nil
    }
    
    private static func getWindowByTitleContains(_ pattern: String) -> (AXUIElement, pid_t)? {
        let allWindows = getAllVisibleWindows()
        let lowercasePattern = pattern.lowercased()
        
        for windowInfo in allWindows {
            if let title = windowInfo.title?.lowercased(),
               title.contains(lowercasePattern) {
                return (windowInfo.window, windowInfo.pid)
            }
        }
        
        log.log("No window found containing: \(pattern)")
        return nil
    }
    
    private static func getAllWindowsForApplication(bundleId: String) -> [(AXUIElement, pid_t)] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
        
        guard let app = apps.first else {
            log.log("Application not found: \(bundleId)")
            return []
        }
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        
        if result == .success, let windows = windowsValue as? [AXUIElement] {
            return windows.map { ($0, pid) }
        }
        
        return []
    }
    
    private static func getAllWindows() -> [(AXUIElement, pid_t)] {
        var allWindowsList: [(AXUIElement, pid_t)] = []
        
        // Iterate through all running applications
        for app in NSWorkspace.shared.runningApplications {
            guard !app.isTerminated,
                  app.activationPolicy == .regular else { continue }
            
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            
            var windowsValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
            
            if result == .success, let windows = windowsValue as? [AXUIElement] {
                // Filter out minimized windows
                for window in windows {
                    var minimized: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                    if let isMinimized = minimized as? Bool, isMinimized {
                        continue
                    }
                    allWindowsList.append((window, pid))
                }
            }
        }
        
        log.log("getAllWindows() found \(allWindowsList.count) windows")
        return allWindowsList
    }
    
    private static func getWindowUnderMouse() -> (AXUIElement, pid_t)? {
        let mouseLocation = NSEvent.mouseLocation
        
        // Convert to screen coordinates (flip Y coordinate)
        guard let screen = NSScreen.main else { return nil }
        let screenFrame = screen.frame
        let flippedY = screenFrame.height - mouseLocation.y
        let point = CGPoint(x: mouseLocation.x, y: flippedY)
        
        // Use accessibility API to find element at point
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element)
        
        if result == .success, let foundElement = element {
            // Walk up the hierarchy to find the window
            var currentElement = foundElement
            var role: CFTypeRef?
            
            while true {
                AXUIElementCopyAttributeValue(currentElement, kAXRoleAttribute as CFString, &role)
                
                if let roleString = role as? String, roleString == kAXWindowRole as String {
                    // Found the window, now get its PID
                    var pid: pid_t = 0
                    AXUIElementGetPid(currentElement, &pid)
                    return (currentElement, pid)
                }
                
                // Get parent element
                var parent: CFTypeRef?
                let parentResult = AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parent)
                
                if parentResult != .success || parent == nil {
                    break
                }
                
                currentElement = parent as! AXUIElement
            }
        }
        
        return nil
    }
    
    private static func getLargestWindow() -> (AXUIElement, pid_t)? {
        let allWindows = getAllVisibleWindows()
        
        let largestWindow = allWindows.max { (window1, window2) in
            (window1.size ?? 0) < (window2.size ?? 0)
        }
        
        guard let window = largestWindow else { return nil }
        return (window.window, window.pid)
    }
    
    private static func getSmallestWindow() -> (AXUIElement, pid_t)? {
        let allWindows = getAllVisibleWindows()
        
        // Filter out windows with no size or zero size
        let validWindows = allWindows.filter { ($0.size ?? 0) > 0 }
        
        let smallestWindow = validWindows.min { (window1, window2) in
            (window1.size ?? CGFloat.greatestFiniteMagnitude) < (window2.size ?? CGFloat.greatestFiniteMagnitude)
        }
        
        guard let window = smallestWindow else { return nil }
        return (window.window, window.pid)
    }
    
    // MARK: - Helper Methods
    
    internal static func getAllVisibleWindows() -> [WindowInfo] {
        var windowInfos: [WindowInfo] = []
        var orderIndex = 0
        
        // Iterate through all running applications
        for app in NSWorkspace.shared.runningApplications {
            guard !app.isTerminated else { continue }
            
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            
            var windowsValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
            
            if result == .success, let windows = windowsValue as? [AXUIElement] {
                for window in windows {
                    // Get window properties
                    let title = getWindowTitle(window)
                    let frame = getWindowFrame(window)
                    
                    // Skip minimized windows
                    var minimized: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                    if let isMinimized = minimized as? Bool, isMinimized {
                        continue
                    }
                    
                    let info = WindowInfo(
                        window: window,
                        pid: pid,
                        application: app,
                        title: title,
                        frame: frame,
                        creationTime: nil,
                        orderIndex: orderIndex
                    )
                    
                    windowInfos.append(info)
                    orderIndex += 1
                }
            }
        }
        
        return windowInfos
    }
    
    private static func getWindowTitle(_ window: AXUIElement) -> String? {
        var titleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        
        if result == .success, let title = titleValue as? String {
            return title
        }
        
        return nil
    }
    
    private static func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        
        let posResult = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
        let sizeResult = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)
        
        if posResult == .success && sizeResult == .success,
           let positionValue = positionValue,
           let sizeValue = sizeValue {
            var position = CGPoint.zero
            var size = CGSize.zero
            
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            
            return CGRect(origin: position, size: size)
        }
        
        return nil
    }
    
    // MARK: - Application Discovery
    
    static func getAllRunningApplications() -> [(bundleId: String, name: String)] {
        var apps: [(bundleId: String, name: String)] = []
        
        for app in NSWorkspace.shared.runningApplications {
            if let bundleId = app.bundleIdentifier,
               let name = app.localizedName,
               !app.isTerminated {
                // Skip system and background apps
                if app.activationPolicy == .regular {
                    apps.append((bundleId: bundleId, name: name))
                }
            }
        }
        
        // Sort alphabetically by name
        apps.sort { $0.name < $1.name }
        
        return apps
    }
    
    // MARK: - Window List Discovery
    
    static func getAllWindowTitles() -> [(title: String, appName: String)] {
        var windowTitles: [(title: String, appName: String)] = []
        
        let allWindows = getAllVisibleWindows()
        
        for windowInfo in allWindows {
            if let title = windowInfo.title,
               !title.isEmpty,
               let appName = windowInfo.application?.localizedName {
                windowTitles.append((title: title, appName: appName))
            }
        }
        
        // Sort alphabetically by title
        windowTitles.sort { $0.title < $1.title }
        
        return windowTitles
    }
}
