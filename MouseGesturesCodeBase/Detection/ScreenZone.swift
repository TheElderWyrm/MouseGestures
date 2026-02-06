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
        // Create CGRect for each zone and use .contains() for reliable detection
        // This envelops the entire zone area instead of just checking borders
        
        let zoneRect: CGRect
        
        switch self {
        case .topLeft:
            // Top-left corner rectangle
            zoneRect = CGRect(
                x: screenFrame.minX,
                y: screenFrame.maxY - cornerSize,
                width: cornerSize,
                height: cornerSize
            )
            
        case .top:
            // Top edge - spans width but excludes corners with buffer
            let leftBoundary = screenFrame.minX + cornerSize + cornerBuffer
            let width = screenFrame.width - 2 * (cornerSize + cornerBuffer)
            zoneRect = CGRect(
                x: leftBoundary,
                y: screenFrame.maxY - threshold,
                width: width,
                height: threshold
            )
            
        case .topRight:
            // Top-right corner rectangle
            zoneRect = CGRect(
                x: screenFrame.maxX - cornerSize,
                y: screenFrame.maxY - cornerSize,
                width: cornerSize,
                height: cornerSize
            )
            
        case .left:
            // Left edge - spans height but excludes corners with buffer
            let bottomBoundary = screenFrame.minY + cornerSize + cornerBuffer
            let height = screenFrame.height - 2 * (cornerSize + cornerBuffer)
            zoneRect = CGRect(
                x: screenFrame.minX,
                y: bottomBoundary,
                width: threshold,
                height: height
            )
            
        case .right:
            // Right edge - spans height but excludes corners with buffer
            let bottomBoundary = screenFrame.minY + cornerSize + cornerBuffer
            let height = screenFrame.height - 2 * (cornerSize + cornerBuffer)
            zoneRect = CGRect(
                x: screenFrame.maxX - threshold,
                y: bottomBoundary,
                width: threshold,
                height: height
            )
            
        case .bottomLeft:
            // Bottom-left corner rectangle
            zoneRect = CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: cornerSize,
                height: cornerSize
            )
            
        case .bottom:
            // Bottom edge - spans width but excludes corners with buffer
            let leftBoundary = screenFrame.minX + cornerSize + cornerBuffer
            let width = screenFrame.width - 2 * (cornerSize + cornerBuffer)
            zoneRect = CGRect(
                x: leftBoundary,
                y: screenFrame.minY,
                width: width,
                height: threshold
            )
            
        case .bottomRight:
            // Bottom-right corner rectangle
            zoneRect = CGRect(
                x: screenFrame.maxX - cornerSize,
                y: screenFrame.minY,
                width: cornerSize,
                height: cornerSize
            )
        }
        
        // Use CGRect.contains for reliable zone detection
        return zoneRect.contains(point)
    }
}
