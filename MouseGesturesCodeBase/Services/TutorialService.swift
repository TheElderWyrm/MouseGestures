import Foundation

/// Possible states for the interactive onboarding tutorial
public enum TutorialState: String, Codable {
    case inactive
    case start
    case clickAddGesture
    case selectAction
    case configureTrigger
    case saveGesture
    case complete
}

/// Service that manages the state of the interactive tutorial walkthrough
public class TutorialService: ObservableObject {
    public static let shared = TutorialService()
    
    @Published public var state: TutorialState = .inactive
    
    private init() {}
    
    public func startTutorial() {
        log.log("Tutorial starting soon...")
        // Add a short delay to allow the UI to transition from Onboarding to TabView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.state = .start
            log.log("Tutorial started")
        }
    }
    
    public func setState(_ newState: TutorialState) {
        state = newState
        log.log("Tutorial state changed to: \(newState)")
    }
    
    public func advance(from currentState: TutorialState, to nextState: TutorialState) {
        if state == currentState {
            setState(nextState)
        }
    }
    
    public func finish() {
        state = .complete
        log.log("Tutorial finished")
        
        // Reset to inactive after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.state = .inactive
        }
    }
    
    public func cancel() {
        state = .inactive
        log.log("Tutorial cancelled")
    }
}
