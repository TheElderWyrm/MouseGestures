import SwiftUI

struct TutorialPopoverModifier: ViewModifier {
    let targetState: TutorialState
    @Binding var currentState: TutorialState
    let text: String
    let edge: Edge

    func body(content: Content) -> some View {
        content
            .popover(isPresented: Binding(
                get: { currentState == targetState },
                set: { show in
                    if !show && currentState == targetState {
                        // If user clicks outside, we don't automatically advance 
                        // unless it's the last step.
                    }
                }
            ), arrowEdge: edge) {
                VStack(spacing: 12) {
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
                        Button("Skip Tutorial") {
                            TutorialService.shared.cancel()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Spacer()

                        Button("Got it") {
                            advanceState()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding()
            }
    }

    private func advanceState() {
        switch targetState {
        case .clickAddGesture:
            currentState = .selectAction
        case .selectAction:
            currentState = .configureTrigger
        case .configureTrigger:
            currentState = .saveGesture
        case .saveGesture:
            TutorialService.shared.finish()
        default:
            break
        }
    }
}

extension View {
    /// Adds a tutorial step popover to the view when the tutorial matches the target state
    func tutorialStep(targetState: TutorialState, currentState: Binding<TutorialState>, text: String, edge: Edge = .bottom) -> some View {
        self.modifier(TutorialPopoverModifier(targetState: targetState, currentState: currentState, text: text, edge: edge))
    }
}
