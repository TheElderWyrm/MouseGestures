import SwiftUI
import AppKit

// MARK: - Bundle Editor View (SwiftUI)

/// Main SwiftUI view for editing bundle actions.
/// Right panel serves dual purpose: add new actions, or edit the selected action.
struct BundleEditorView: View {
    @State var bundledActions: [BundledAction]
    @State var stopOnFailure: Bool
    @State var parallelExecution: Bool
    let onDone: ([BundledAction], Bool, Bool) -> Void
    let onCancel: () -> Void
    
    @State private var selection: UUID?
    
    // Right-panel editor state (shared for add & edit modes)
    @State private var editorActionId: String = ""
    @State private var editorParams: [String: AnyCodable] = [:]
    @State private var editorDelay: String = "0.2"
    
    /// Tracks whether we're actively loading a selection to avoid feedback loops
    @State private var isLoadingSelection = false
    
    private var isEditing: Bool { selection != nil }
    
    private var editingIndex: Int? {
        guard let sel = selection else { return nil }
        return bundledActions.firstIndex(where: { $0.id == sel })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            
            HSplitView {
                actionListPanel
                    .frame(minWidth: 280, idealWidth: 320)
                rightPanel
                    .frame(minWidth: 300, idealWidth: 420)
            }
            
            Divider()
            footerBar
        }
        .frame(width: 780, height: 640)
        .onChange(of: selection) { newSel in
            loadSelectionIntoEditor(newSel)
        }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)
            Text("Edit Bundle Actions")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Text("\(bundledActions.count) action\(bundledActions.count == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Action List Panel (Left)
    
    private var actionListPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Actions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                // New action button when editing
                if isEditing {
                    Button(action: { selection = nil }) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 10))
                            Text("New")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Deselect and add a new action")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            if bundledActions.isEmpty {
                emptyListPlaceholder
            } else {
                actionList
            }
            
            Divider()
            
            // Bundle settings
            bundleSettingsBar
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    private var emptyListPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Actions")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            Text("Select an action from the right panel\nand click \"Add to Bundle\"")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var actionList: some View {
        List(selection: $selection) {
            ForEach(bundledActions.indices, id: \.self) { index in
                let action = bundledActions[index]
                BundleActionRow(
                    action: action,
                    index: index,
                    isFirst: index == 0,
                    isLast: index == bundledActions.count - 1,
                    delay: Binding(
                        get: { action.delayAfter ?? 0.2 },
                        set: { newVal in
                            bundledActions[index].delayAfter = newVal
                        }
                    ),
                    onMoveUp: { moveAction(action, direction: -1) },
                    onMoveDown: { moveAction(action, direction: 1) },
                    onDuplicate: { duplicateAction(action) },
                    onRemove: { removeAction(action) }
                )
                .tag(action.id)
            }
            .onMove(perform: reorderActions)
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
    }
    
    private var bundleSettingsBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $stopOnFailure) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.octagon")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Stop on failure")
                        .font(.system(size: 12))
                }
            }
            .toggleStyle(.checkbox)
            
            Toggle(isOn: $parallelExecution) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Parallel execution")
                        .font(.system(size: 12))
                }
            }
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Right Panel (Add / Edit)
    
    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Panel header — changes based on mode
            HStack(spacing: 6) {
                if isEditing, let idx = editingIndex {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                    Text("Editing Action #\(idx + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                    Text("Add Action")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Action selection + params
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ActionSelectionView(
                        selectedActionId: $editorActionId,
                        actionParameters: $editorParams
                    )
                    
                    // Delay field
                    GroupBox("Delay After") {
                        HStack(spacing: 8) {
                            TextField("0.2", text: $editorDelay)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("seconds")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            
            Divider()
            
            // Action buttons
            HStack {
                if isEditing {
                    Button(action: { removeSelectedAction() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                            Text("Remove")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.red)
                    }
                    .controlSize(.large)
                }
                
                Spacer()
                
                if isEditing {
                    Button(action: applyEdits) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Update Action")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .controlSize(.large)
                    .disabled(editorActionId.isEmpty)
                } else {
                    Button(action: addActionToBundle) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                            Text("Add to Bundle")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .controlSize(.large)
                    .disabled(editorActionId.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }
    
    // MARK: - Footer
    
    private var footerBar: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .keyboardShortcut(.escape, modifiers: [])
            Spacer()
            Button("Done") { onDone(bundledActions, stopOnFailure, parallelExecution) }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Selection ↔ Editor Sync
    
    private func loadSelectionIntoEditor(_ newSel: UUID?) {
        if let sel = newSel, let action = bundledActions.first(where: { $0.id == sel }) {
            isLoadingSelection = true
            editorActionId = action.actionIdentifier
            let savedParams = action.parameters
            let savedDelay = action.delayAfter ?? 0.2
            DispatchQueue.main.async {
                editorParams = savedParams
                editorDelay = String(format: "%.1f", savedDelay)
                isLoadingSelection = false
            }
        } else {
            // Switching to add mode — clear editor
            editorActionId = ""
            editorParams.removeAll()
            editorDelay = "0.2"
        }
    }
    
    // MARK: - Add / Edit Actions
    
    private func addActionToBundle() {
        guard !editorActionId.isEmpty else { return }
        let action = BundledAction(
            actionIdentifier: editorActionId,
            parameters: editorParams,
            delayAfter: Double(editorDelay) ?? 0.2
        )
        bundledActions.append(action)
        
        // Deselect so the editor resets for adding the next action
        selection = nil
    }
    
    private func applyEdits() {
        guard let sel = selection,
              let idx = bundledActions.firstIndex(where: { $0.id == sel }),
              !editorActionId.isEmpty else { return }
        bundledActions[idx].actionIdentifier = editorActionId
        bundledActions[idx].parameters = editorParams
        bundledActions[idx].delayAfter = Double(editorDelay) ?? 0.2
    }
    
    // MARK: - List Manipulation
    
    private func removeAction(_ action: BundledAction) {
        if selection == action.id { selection = nil }
        bundledActions.removeAll { $0.id == action.id }
    }
    
    private func removeSelectedAction() {
        guard let sel = selection,
              let action = bundledActions.first(where: { $0.id == sel }) else { return }
        removeAction(action)
    }
    
    private func duplicateAction(_ action: BundledAction) {
        var copy = action
        copy.id = UUID()
        if let idx = bundledActions.firstIndex(where: { $0.id == action.id }) {
            bundledActions.insert(copy, at: idx + 1)
            selection = copy.id
        }
    }
    
    private func moveAction(_ action: BundledAction, direction: Int) {
        guard let idx = bundledActions.firstIndex(where: { $0.id == action.id }) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0, newIdx < bundledActions.count else { return }
        bundledActions.swapAt(idx, newIdx)
    }
    
    private func reorderActions(from source: IndexSet, to destination: Int) {
        bundledActions.move(fromOffsets: source, toOffset: destination)
    }
    
    // MARK: - Computed
    
    private var selectedIndex: Int? {
        guard let sel = selection else { return nil }
        return bundledActions.firstIndex(where: { $0.id == sel })
    }
    
    private var canMoveUp: Bool {
        guard let idx = selectedIndex else { return false }
        return idx > 0
    }
    
    private var canMoveDown: Bool {
        guard let idx = selectedIndex else { return false }
        return idx < bundledActions.count - 1
    }
}

// MARK: - Bundle Action Row

struct BundleActionRow: View {
    let action: BundledAction
    let index: Int
    let isFirst: Bool
    let isLast: Bool
    @Binding var delay: TimeInterval
    
    // Action closures from parent
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDuplicate: () -> Void
    let onRemove: () -> Void
    
    @State private var isHovered = false
    @State private var isEditingDelay = false
    @State private var delayText: String = ""
    
    var body: some View {
        HStack(spacing: 8) {
            // Order number
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 22, alignment: .center)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
            
            // Condition indicator
            if action.condition != nil && !(action.condition?.conditions.isEmpty ?? true) {
                Image(systemName: "questionmark.diamond.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .help("Has condition: \(action.condition?.displayString ?? "")")
            }
            
            // Action icon + name
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let (_, pluginAction) = PluginManager.shared.getAction(identifier: action.actionIdentifier),
                       let icon = pluginAction.icon {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                    Text(actionDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                
                if !action.parameters.isEmpty {
                    Text(parameterSummary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Inline control buttons (visible on hover)
            if isHovered {
                HStack(spacing: 2) {
                    rowButton(icon: "chevron.up", help: "Move Up", disabled: isFirst, action: onMoveUp)
                    rowButton(icon: "chevron.down", help: "Move Down", disabled: isLast, action: onMoveDown)
                    rowButton(icon: "doc.on.doc", help: "Duplicate", action: onDuplicate)
                    rowButton(icon: "trash", help: "Remove", isDestructive: true, action: onRemove)
                }
                .transition(.opacity)
            } else {
                // Delay (shown when not hovered)
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    if isEditingDelay {
                        TextField("", text: $delayText, onCommit: commitDelay)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 42)
                            .font(.system(size: 11, design: .monospaced))
                            .onAppear { delayText = String(format: "%.1f", delay) }
                    } else {
                        Text(String(format: "%.1fs", delay))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .onTapGesture { isEditingDelay = true }
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Duplicate") { onDuplicate() }
            Divider()
            if !isFirst {
                Button("Move Up") { onMoveUp() }
            }
            if !isLast {
                Button("Move Down") { onMoveDown() }
            }
            Divider()
            Button("Remove", role: .destructive) { onRemove() }
        }
    }
    
    @ViewBuilder
    private func rowButton(icon: String, help: String, disabled: Bool = false, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(disabled ? .secondary.opacity(0.3) : (isDestructive ? .red : .secondary))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
    }
    
    private var actionDisplayName: String {
        if let (_, pluginAction) = PluginManager.shared.getAction(identifier: action.actionIdentifier) {
            return pluginAction.name
        }
        return action.actionIdentifier
    }
    
    private var parameterSummary: String {
        let params = action.parameters.compactMap { key, val -> String? in
            guard let v = val.value as? String, !v.isEmpty else {
                if let v = val.value as? Bool { return "\(key): \(v ? "yes" : "no")" }
                if let v = val.value as? Double { return "\(key): \(v)" }
                if let v = val.value as? Int { return "\(key): \(v)" }
                return nil
            }
            return "\(key): \(v)"
        }
        return params.prefix(2).joined(separator: ", ")
    }
    
    private func commitDelay() {
        if let val = Double(delayText), val >= 0 {
            delay = val
        }
        isEditingDelay = false
    }
}

// MARK: - Make BundledAction Identifiable

extension BundledAction: Identifiable {}

// MARK: - SwiftUI Window Host for Bundle Editor

/// Manages presenting the BundleEditorView as an NSWindow sheet.
class BundleEditorWindowHost {
    
    private var hostingController: NSHostingController<BundleEditorView>?
    private var editorWindow: NSWindow?
    
    func present(
        bundledActions: [BundledAction],
        stopOnFailure: Bool,
        parallelExecution: Bool,
        parentWindow: NSWindow,
        completion: @escaping ([BundledAction], Bool, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let editorView = BundleEditorView(
            bundledActions: bundledActions,
            stopOnFailure: stopOnFailure,
            parallelExecution: parallelExecution,
            onDone: { [weak self] actions, stop, parallel in
                self?.dismiss(parentWindow: parentWindow)
                completion(actions, stop, parallel)
            },
            onCancel: { [weak self] in
                self?.dismiss(parentWindow: parentWindow)
                onCancel()
            }
        )
        
        let controller = NSHostingController(rootView: editorView)
        self.hostingController = controller
        
        let window = NSWindow(contentViewController: controller)
        window.title = "Edit Bundle Actions"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 780, height: 640))
        window.minSize = NSSize(width: 640, height: 500)
        self.editorWindow = window
        
        objc_setAssociatedObject(parentWindow, "bundleEditorHost", self, .OBJC_ASSOCIATION_RETAIN)
        
        parentWindow.beginSheet(window) { _ in
            objc_setAssociatedObject(parentWindow, "bundleEditorHost", nil, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    private func dismiss(parentWindow: NSWindow) {
        if let w = editorWindow {
            parentWindow.endSheet(w)
        }
        editorWindow = nil
        hostingController = nil
    }
}
