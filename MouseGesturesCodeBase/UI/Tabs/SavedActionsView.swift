import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Saved Actions Tab
struct SavedActionsView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedActions = Set<UUID>()
    @State private var searchText = ""
    enum ActiveSheet: Identifiable {
        case addAction
        case editAction(SavedAction)
        
        var id: String {
            switch self {
            case .addAction: return "add"
            case .editAction(let a): return "edit-\(a.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var showingDeleteConfirmation = false
    @State private var actionsToDelete: [SavedAction] = []
    @State private var showingExportPanel = false
    @State private var showingImportPanel = false
    @State private var sortOrder = SavedActionsSortService.SortOrder.dateModified
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            if filteredAndSortedActions.isEmpty {
                MGEmptyState(
                    icon: "star.square.on.square",
                    title: "No Saved Actions",
                    description: "Saved actions are reusable action configurations that can be quickly applied to gestures.",
                    actionLabel: "Add Your First Saved Action",
                    action: { activeSheet = .addAction }
                )
            } else {
                actionListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addAction:
                AddSavedActionSheet()
            case .editAction(let action):
                EditSavedActionSheet(action: action)
            }
        }
        .confirmationDialog(
            "Delete Saved Actions",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelectedActions() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = actionsToDelete.count
            if count == 1 {
                Text("Are you sure you want to delete \"\(actionsToDelete.first?.name ?? "")\"?")
            } else {
                Text("Are you sure you want to delete \(count) saved actions?")
            }
        }
        .fileExporter(
            isPresented: $showingExportPanel,
            document: SavedActionsDocument(actions: Array(selectedActions.compactMap { id in 
                uiServices.getSavedAction(byId: id)
            })),
            contentType: .json,
            defaultFilename: "SavedActions.json"
        ) { result in
            switch result {
            case .success(let url): log.log("Exported saved actions to: \(url.path)")
            case .failure(let error): log.log("Failed to export saved actions: \(error)")
            }
        }
        .fileImporter(
            isPresented: $showingImportPanel,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importActions(from: url) }
            case .failure(let error):
                log.log("Failed to import saved actions: \(error)")
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        MGPageHeader("Saved Actions") {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(SavedActionsSortService.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            
            MGSearchField("Search saved actions...", text: $searchText)
                .frame(width: MGStyle.Layout.searchFieldWidth)
            
            MGHeaderDivider()
            
            Button(action: { activeSheet = .addAction }) {
                Label("Add", systemImage: "plus")
            }
            Button(action: editSelectedAction) {
                Label("Edit", systemImage: "pencil")
            }
            .disabled(selectedActions.count != 1)
            
            Button(action: confirmDeleteSelectedActions) {
                Label("Remove", systemImage: "minus")
            }
            .disabled(selectedActions.isEmpty)
            
            MGHeaderDivider()
            
            Button(action: { showingImportPanel = true }) {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            Button(action: { showingExportPanel = true }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(selectedActions.isEmpty)
        }
    }
    
    private var actionListView: some View {
        ScrollView {
            LazyVStack(spacing: MGStyle.Spacing.md) {
                ForEach(filteredAndSortedActions) { action in
                    SavedActionRow(
                        action: action,
                        isSelected: selectedActions.contains(action.id),
                        onToggleSelection: { toggleSelection(for: action) },
                        onEdit: { editAction(action) },
                        onDelete: { confirmDeleteAction(action) },
                        onDoubleClick: { editAction(action) }
                    )
                }
            }
            .padding(MGStyle.Spacing.xl)
        }
    }
    
    // MARK: - Helper Methods
    
    private var filteredAndSortedActions: [SavedAction] {
        let actions = uiServices.savedActions
        let filtered = uiServices.filterSavedActions(actions, searchText: searchText)
        return uiServices.sortSavedActions(filtered, by: sortOrder)
    }
    
    private func toggleSelection(for action: SavedAction) {
        if selectedActions.contains(action.id) {
            selectedActions.remove(action.id)
        } else {
            selectedActions.insert(action.id)
        }
    }
    
    private func editSelectedAction() {
        if let id = selectedActions.first,
           let action = uiServices.getSavedAction(byId: id) {
            editAction(action)
        }
    }
    
    private func editAction(_ action: SavedAction) {
        activeSheet = .editAction(action)
    }
    
    private func confirmDeleteAction(_ action: SavedAction) {
        actionsToDelete = [action]
        showingDeleteConfirmation = true
    }
    
    private func confirmDeleteSelectedActions() {
        actionsToDelete = selectedActions.compactMap { id in
            uiServices.getSavedAction(byId: id)
        }
        showingDeleteConfirmation = true
    }
    
    private func deleteSelectedActions() {
        for action in actionsToDelete {
            uiServices.deleteSavedAction(action)
            selectedActions.remove(action.id)
        }
        actionsToDelete = []
    }
    
    private func importActions(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            _ = uiServices.importSavedActions(from: data, replaceExisting: false)
        } catch {
            log.log("Failed to import saved actions: \(error)")
        }
    }
}

// MARK: - Saved Action Row

struct SavedActionRow: View {
    let action: SavedAction
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDoubleClick: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            // Selection Checkbox
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .imageScale(.large)
                .contentShape(Rectangle())
                .onTapGesture { onToggleSelection() }
            
            // Action Icon
            Image(systemName: getActionIcon())
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            // Action Details
            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                Text(action.name)
                    .font(.system(.body, weight: .semibold))
                
                HStack {
                    MGBadge(action.typeDisplayName)
                    
                    Text(action.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Date Modified
            Text(formatDate(action.dateModified))
                .font(.caption)
                .foregroundColor(.secondary)
            
            if isHovered {
                MGRowActions(actions: [
                    .init("pencil") { onEdit() },
                    .init("trash", destructive: true) { onDelete() }
                ])
            }
        }
        .padding(.horizontal, MGStyle.Spacing.lg)
        .padding(.vertical, MGStyle.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : 
                      (isHovered ? MGStyle.Colors.cardBackground : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in isHovered = hovering }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
    }
    
    private func getActionIcon() -> String {
        return UIServices.shared.getIconForSavedAction(action)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Saved Actions Document

struct SavedActionsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    let actions: [SavedAction]
    
    init(actions: [SavedAction]) {
        self.actions = actions
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        actions = try JSONDecoder().decode([SavedAction].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(actions)
        return FileWrapper(regularFileWithContents: data)
    }
}
