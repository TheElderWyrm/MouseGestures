import SwiftUI

struct TutorialPopoverModifier: ViewModifier {
    let targetState: TutorialState
    let currentState: TutorialState
    let text: String
    let edge: Edge
    
    func body(content: Content) -> some View {
        content
            .popover(isPresented: Binding(
                get: { currentState == targetState },
                set: { _ in } // Managed by TutorialService
            ), arrowEdge: edge) {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.orange)
                        Text("Tutorial Step")
                            .font(.headline)
                        Spacer()
                    }
                    
                    Text(text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 250, alignment: .leading)
                    
                    HStack {
                        Spacer()
                        Button("Got it") {
                            // Optionally advance or just let them click the target
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                .padding()
            }
    }
}

extension View {
    /// Adds a tutorial step popover to the view when the tutorial matches the target state
    func tutorialStep(targetState: TutorialState, currentState: TutorialState, text: String, edge: Edge = .bottom) -> some View {
        self.modifier(TutorialPopoverModifier(targetState: targetState, currentState: currentState, text: text, edge: edge))
    }
}
