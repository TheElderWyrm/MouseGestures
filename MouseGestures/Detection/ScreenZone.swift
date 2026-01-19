import Cocoa

enum ScreenZone: String, CaseIterable, Codable {
    case topLeft = "Top Left Corner"
    case top = "Top Edge"
    case topRight = "Top Right Corner"
    case left = "Left Edge"
    case right = "Right Edge"
    case bottomLeft = "Bottom Left Corner"
    case bottom = "Bottom Edge"
    case bottomRight = "Bottom Right Corner"
    
    var displayName: String {
        return self.rawValue
    }
    
    func contains(point: NSPoint, screenFrame: NSRect, threshold: CGFloat = 30, cornerSize: CGFloat = 30, cornerBuffer: CGFloat = 0) -> Bool {
        // For corners, use cornerSize; for edges use threshold
        // Corner buffer creates a dead zone around corners where edges won't activate
        
        switch self {
        case .topLeft:
            return point.x <= screenFrame.minX + cornerSize &&
                   point.y >= screenFrame.maxY - cornerSize
        case .top:
            // Top edge excludes corner areas plus buffer zone
            let leftBoundary = screenFrame.minX + cornerSize + cornerBuffer
            let rightBoundary = screenFrame.maxX - cornerSize - cornerBuffer
            return point.y >= screenFrame.maxY - threshold &&
                   point.x > leftBoundary &&
                   point.x < rightBoundary
        case .topRight:
            return point.x >= screenFrame.maxX - cornerSize &&
                   point.y >= screenFrame.maxY - cornerSize
        case .left:
            // Left edge excludes corner areas plus buffer zone
            let topBoundary = screenFrame.maxY - cornerSize - cornerBuffer
            let bottomBoundary = screenFrame.minY + cornerSize + cornerBuffer
            return point.x <= screenFrame.minX + threshold &&
                   point.y < topBoundary &&
                   point.y > bottomBoundary
        case .right:
            // Right edge excludes corner areas plus buffer zone
            let topBoundary = screenFrame.maxY - cornerSize - cornerBuffer
            let bottomBoundary = screenFrame.minY + cornerSize + cornerBuffer
            return point.x >= screenFrame.maxX - threshold &&
                   point.y < topBoundary &&
                   point.y > bottomBoundary
        case .bottomLeft:
            return point.x <= screenFrame.minX + cornerSize &&
                   point.y <= screenFrame.minY + cornerSize
        case .bottom:
            // Bottom edge excludes corner areas plus buffer zone
            let leftBoundary = screenFrame.minX + cornerSize + cornerBuffer
            let rightBoundary = screenFrame.maxX - cornerSize - cornerBuffer
            return point.y <= screenFrame.minY + threshold &&
                   point.x > leftBoundary &&
                   point.x < rightBoundary
        case .bottomRight:
            return point.x >= screenFrame.maxX - cornerSize &&
                   point.y <= screenFrame.minY + cornerSize
        }
    }
}
