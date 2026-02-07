import SwiftUI

// MARK: - Settings Provider Protocol

/// Single protocol for anything that provides settings entries.
/// Each entry specifies what category it belongs to — categories are created automatically.
protocol SettingsProvider {
    /// The settings entries this provider contributes.
    var settingsEntries: [SettingsEntry] { get }
}

// MARK: - Settings Category Descriptor

/// Lightweight description of a settings category. Multiple entries can target the same
/// category ID; the registry uses the lowest-order descriptor for the sidebar metadata.
struct SettingsCategoryDescriptor {
    let id: String
    let title: String
    let icon: String
    /// Sidebar sort order — lower values appear higher
    let order: Int
}

// MARK: - Settings Entry

/// A single item (or group of items) contributed to a settings category.
struct SettingsEntry {
    /// Which category this entry belongs to — the category is created if it doesn't exist yet
    let category: SettingsCategoryDescriptor
    /// Sort order within the category (lower = higher position)
    let order: Int
    /// Whether this entry requires the Advanced toggle
    let isAdvanced: Bool
    /// Searchable metadata for the settings search
    let searchableItems: [SearchableSettingItem]
    /// Builds the SwiftUI view for this entry
    let viewBuilder: @MainActor (_ showAdvanced: Binding<Bool>) -> AnyView
    
    init(
        category: SettingsCategoryDescriptor,
        order: Int = 50,
        isAdvanced: Bool = false,
        searchableItems: [SearchableSettingItem] = [],
        viewBuilder: @escaping @MainActor (_ showAdvanced: Binding<Bool>) -> AnyView
    ) {
        self.category = category
        self.order = order
        self.isAdvanced = isAdvanced
        self.searchableItems = searchableItems
        self.viewBuilder = viewBuilder
    }
}

// MARK: - Searchable Setting Item

/// Represents a single searchable setting for the settings search.
struct SearchableSettingItem {
    let title: String
    let description: String
    let keywords: [String]
    
    func matches(query: String) -> Bool {
        let q = query.lowercased()
        return title.lowercased().contains(q) ||
               description.lowercased().contains(q) ||
               keywords.contains { $0.lowercased().contains(q) }
    }
}

// MARK: - Resolved Category

/// A category assembled from all entries that share the same category ID.
struct ResolvedCategory {
    let id: String
    let title: String
    let icon: String
    let order: Int
    let entries: [SettingsEntry]
    
    /// All searchable items across all entries in this category
    var allSearchableItems: [SearchableSettingItem] {
        entries.flatMap(\.searchableItems)
    }
}

// MARK: - Settings Category Registry

/// Central registry that collects settings entries, auto-groups them by category,
/// and provides search. The Settings tab reads entirely from this registry.
class SettingsCategoryRegistry: ObservableObject {
    static let shared = SettingsCategoryRegistry()
    
    @Published private(set) var entries: [SettingsEntry] = []
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register all entries from a settings provider.
    func register(_ provider: any SettingsProvider) {
        entries.append(contentsOf: provider.settingsEntries)
    }
    
    /// Register a single entry directly.
    func register(entry: SettingsEntry) {
        entries.append(entry)
    }
    
    /// Remove all entries (call before re-discovery to avoid duplicates).
    func clear() {
        entries.removeAll()
    }
    
    // MARK: - Resolved Categories
    
    /// All categories, assembled from entries, sorted by category order.
    var categories: [ResolvedCategory] {
        // Group entries by category ID
        var grouped: [String: (descriptor: SettingsCategoryDescriptor, entries: [SettingsEntry])] = [:]
        
        for entry in entries {
            let catId = entry.category.id
            if var existing = grouped[catId] {
                existing.entries.append(entry)
                // Use descriptor with lowest order for sidebar metadata
                if entry.category.order < existing.descriptor.order {
                    existing.descriptor = entry.category
                }
                grouped[catId] = existing
            } else {
                grouped[catId] = (entry.category, [entry])
            }
        }
        
        return grouped.values
            .map { info in
                ResolvedCategory(
                    id: info.descriptor.id,
                    title: info.descriptor.title,
                    icon: info.descriptor.icon,
                    order: info.descriptor.order,
                    entries: info.entries.sorted { $0.order < $1.order }
                )
            }
            .sorted { $0.order < $1.order }
    }
    
    /// Get a single resolved category by ID
    func category(id: String) -> ResolvedCategory? {
        categories.first { $0.id == id }
    }
    
    // MARK: - Search
    
    /// All searchable items with their category context
    private var allSearchableItems: [(categoryId: String, categoryTitle: String, item: SearchableSettingItem)] {
        var items: [(String, String, SearchableSettingItem)] = []
        for cat in categories {
            for item in cat.allSearchableItems {
                items.append((cat.id, cat.title, item))
            }
        }
        return items
    }
    
    /// Returns category IDs that match the query. Empty query returns all.
    func matchingCategoryIds(for query: String) -> Set<String> {
        guard !query.isEmpty else {
            return Set(categories.map(\.id))
        }
        var result = Set<String>()
        for (catId, catTitle, item) in allSearchableItems {
            if catTitle.lowercased().contains(query.lowercased()) || item.matches(query: query) {
                result.insert(catId)
            }
        }
        return result
    }
    
    /// Returns individual matching items for the search dropdown.
    func searchResults(for query: String) -> [(categoryId: String, categoryTitle: String, item: SearchableSettingItem)] {
        guard !query.isEmpty else { return [] }
        return allSearchableItems.filter { $0.item.matches(query: query) }
    }
}
