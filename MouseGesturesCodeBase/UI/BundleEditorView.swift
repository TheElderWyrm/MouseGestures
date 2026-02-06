import SwiftUI
import AppKit

// MARK: - Bundle Editor View (SwiftUI)

/// Main SwiftUI view for editing bundle actions, replacing the old AppKit BundleActionsEditor.
/// Presented as a sheet window via NSHostingController from BundleActionsPlugin.
struct BundleEditorView: View {
    @State var bundledActions: [BundledAction]
    let onDone: ([BundledAction]) -> Void
    let onCancel: () -> Void
    
    @State private var selection: UUID?
    @State private var editingAction: BundledAction?
    @State private var isAddingSectionExpanded = true
    
    // Add-action state
    @State private var newActionId: String = ""
    @State private var newActionParams: [String: AnyCodable] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
            
            Divider()
            
            // Content
            HSplitView {
                actionListPanel
                    .frame(minWidth: 280, idealWidth: 320)
                
                addActionPanel
                    .frame(minWidth: 300, idealWidth: 340)
            }
            
            Divider()
            
            // Footer
            footerBar
        }
        .frame(width: 740, height: 620)
        .sheet(item: $editingAction) { action in
            BundleActionEditView(
                bundledAction: action,
                onSave: { edited in
                    if let idx = bundledActions.firstIndex(where: { $0.id == edited.id }) {
                        bundledActions[idx] = edited
                    }
                    editingAction = nil
                },
                onCancel: { editingAction = nil }
            )
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
    
    // MARK: - Action List Panel
    
    private var actionListPanel: some View {
        VStack(spacing: 0) {
            // List header
            HStack {
                Text("Actions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
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
            
            // List toolbar
            listToolbar
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
            ForEach(Array(bundledActions.enumerated()), id: \.element.id) { index, action in
                BundleActionRow(
                    action: action,
                    index: index,
                    delay: Binding(
                        get: { action.delayAfter ?? 0.2 },
                        set: { newVal in
                            if let idx = bundledActions.firstIndex(where: { $0.id == action.id }) {
                                bundledActions[idx].delayAfter = newVal
                            }
                        }
                    )
                )
                .tag(action.id)
                .contextMenu {
                    Button("Edit...") { editingAction = action }
                    Button("Duplicate") { duplicateAction(action) }
                    Divider()
                    if index > 0 {
                        Button("Move Up") { moveAction(action, direction: -1) }
                    }
                    if index < bundledActions.count - 1 {
                        Button("Move Down") { moveAction(action, direction: 1) }
                    }
                    Divider()
                    Button("Remove", role: .destructive) { removeAction(action) }
                }
            }
            .onMove(perform: reorderActions)
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
    }
    
    private var listToolbar: some View {
        HStack(spacing: 4) {
            // Move buttons
            Button(action: { moveSelectedAction(direction: -1) }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveUp)
            .help("Move Up")
            
            Button(action: { moveSelectedAction(direction: 1) }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveDown)
            .help("Move Down")
            
            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)
            
            Button(action: { editSelectedAction() }) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .help("Edit Action")
            
            Button(action: { duplicateSelectedAction() }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .help("Duplicate Action")
            
            Button(action: { removeSelectedAction() }) {
                Image(systemName: "minus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .help("Remove Action")
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Add Action Panel
    
    private var addActionPanel: some View {
        VStack(spacing: 0) {
            // Panel header
            HStack {
                Text("Add Action")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Action selection
            ScrollView {
                VStack(spacing: 12) {
                    ActionSelectionView(
                        selectedActionId: $newActionId,
                        actionParameters: $newActionParams
                    )
                }
                .padding(12)
            }
            
            Divider()
            
            // Add button
            HStack {
                Spacer()
                Button(action: addActionToBundle) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Add to Bundle")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .controlSize(.large)
                .disabled(newActionId.isEmpty)
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
            
            Button("Done") { onDone(bundledActions) }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func addActionToBundle() {
        guard !newActionId.isEmpty else { return }
        let action = BundledAction(
            actionIdentifier: newActionId,
            parameters: newActionParams,
            delayAfter: 0.2
        )
        bundledActions.append(action)
        selection = action.id
        
        // Reset for next action
        newActionId = ""
        newActionParams.removeAll()
    }
    
    private func removeAction(_ action: BundledAction) {
        bundledActions.removeAll { $0.id == action.id }
        if selection == action.id { selection = nil }
    }
    
    private func removeSelectedAction() {
        guard let sel = selection,
              let action = bundledActions.first(where: { $0.id == sel }) else { return }
        removeAction(action)
    }
    
    private func editSelectedAction() {
        guard let sel = selection,
              let action = bundledActions.first(where: { $0.id == sel }) else { return }
        editingAction = action
    }
    
    private func duplicateAction(_ action: BundledAction) {
        var copy = action
        copy.id = UUID()
        if let idx = bundledActions.firstIndex(where: { $0.id == action.id }) {
            bundledActions.insert(copy, at: idx + 1)
            selection = copy.id
        }
    }
    
    private func duplicateSelectedAction() {
        guard let sel = selection,
              let action = bundledActions.first(where: { $0.id == sel }) else { return }
        duplicateAction(action)
    }
    
    private func moveAction(_ action: BundledAction, direction: Int) {
        guard let idx = bundledActions.firstIndex(where: { $0.id == action.id }) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0, newIdx < bundledActions.count else { return }
        bundledActions.swapAt(idx, newIdx)
    }
    
    private func moveSelectedAction(direction: Int) {
        guard let sel = selection,
              let action = bundledActions.first(where: { $0.id == sel }) else { return }
        moveAction(action, direction: direction)
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
    @Binding var delay: TimeInterval
    
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
                
                // Parameter summary
                if !action.parameters.isEmpty {
                    Text(parameterSummary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Delay
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
        .padding(.vertical, 3)
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

// MARK: - Bundle Action Edit View (Sheet)

struct BundleActionEditView: View {
    @State var bundledAction: BundledAction
    let onSave: (BundledAction) -> Void
    let onCancel: () -> Void
    
    @State private var selectedActionId: String
    @State private var actionParameters: [String: AnyCodable]
    @State private var delayText: String
    
    init(bundledAction: BundledAction, onSave: @escaping (BundledAction) -> Void, onCancel: @escaping () -> Void) {
        self._bundledAction = State(initialValue: bundledAction)
        self.onSave = onSave
        self.onCancel = onCancel
        self._selectedActionId = State(initialValue: bundledAction.actionIdentifier)
        self._actionParameters = State(initialValue: bundledAction.parameters)
        self._delayText = State(initialValue: String(format: "%.1f", bundledAction.delayAfter ?? 0.2))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                Text("Edit Action")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 16) {
                    ActionSelectionView(
                        selectedActionId: $selectedActionId,
                        actionParameters: $actionParameters
                    )
                    
                    GroupBox("Delay After") {
                        HStack {
                            TextField("Delay (seconds)", text: $delayText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("seconds")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(16)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Save") { saveAction() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedActionId.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 600, height: 540)
    }
    
    private func saveAction() {
        bundledAction.actionIdentifier = selectedActionId
        bundledAction.parameters = actionParameters
        bundledAction.delayAfter = Double(delayText) ?? 0.2
        onSave(bundledAction)
    }
}

// MARK: - Make BundledAction Identifiable for sheet presentation

extension BundledAction: Identifiable {}

// MARK: - SwiftUI Window Host for Bundle Editor

/// Manages presenting the BundleEditorView as an NSWindow sheet.
/// Called from BundleActionsPlugin.presentAdvancedConfiguration.
class BundleEditorWindowHost {
    
    private var hostingController: NSHostingController<BundleEditorView>?
    private var editorWindow: NSWindow?
    
    func present(
        bundledActions: [BundledAction],
        parentWindow: NSWindow,
        completion: @escaping ([BundledAction]?) -> Void
    ) {
        let editorView = BundleEditorView(
            bundledActions: bundledActions,
            onDone: { [weak self] result in
                self?.dismiss(parentWindow: parentWindow)
                completion(result)
            },
            onCancel: { [weak self] in
                self?.dismiss(parentWindow: parentWindow)
                completion(nil)
            }
        )
        
        let controller = NSHostingController(rootView: editorView)
        self.hostingController = controller
        
        let window = NSWindow(contentViewController: controller)
        window.title = "Edit Bundle Actions"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 740, height: 620))
        window.minSize = NSSize(width: 600, height: 500)
        self.editorWindow = window
        
        // Retain self for the duration of the sheet
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
