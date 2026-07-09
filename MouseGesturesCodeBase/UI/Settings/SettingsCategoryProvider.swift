import SwiftUI

// MARK: - Settings Provider Protocol

/// Single protocol for anything that provides settings entries.
/// Each entry specifies what category (and optionally subcategory) it belongs to.
/// Categories and subcategories are created automatically from whatever entries exist.
protocol SettingsProvider {
    var settingsEntries: [SettingsEntry] { get }
}

// MARK: - Settings Category Descriptor

/// Lightweight description of a settings category. The registry auto-creates
/// categories from entries; the lowest-order descriptor wins for sidebar metadata.
struct SettingsCategoryDescriptor {
    let id: String
    let title: String
    let icon: String
    /// Sidebar sort order — lower values appear higher
    let order: Int
}

// MARK: - Settings Subcategory Descriptor

/// Optional grouping within a category. When entries in a category have subcategories,
/// the settings view shows a segmented picker to switch between them.
struct SettingsSubcategoryDescriptor {
    let id: String
    let title: String
    let icon: String
    /// Sort order within the category's subcategory picker
    let order: Int
}

// MARK: - Settings Entry

/// A single item (or group of items) contributed to a settings category.
struct SettingsEntry {
    /// Which category this entry belongs to
    let category: SettingsCategoryDescriptor
    /// Optional subcategory within the category (triggers a segmented picker)
    let subcategory: SettingsSubcategoryDescriptor?
    /// Sort order within the (sub)category
    let order: Int
    /// Whether this entry requires the Advanced toggle
    let isAdvanced: Bool
    /// Searchable metadata for settings search
    let searchableItems: [SearchableSettingItem]
    /// Builds the SwiftUI view for this entry
    let viewBuilder: @MainActor (_ showAdvanced: Binding<Bool>) -> AnyView

    init(
        category: SettingsCategoryDescriptor,
        subcategory: SettingsSubcategoryDescriptor? = nil,
        order: Int = 50,
        isAdvanced: Bool = false,
        searchableItems: [SearchableSettingItem] = [],
        viewBuilder: @escaping @MainActor (_ showAdvanced: Binding<Bool>) -> AnyView
    ) {
        self.category = category
        self.subcategory = subcategory
        self.order = order
        self.isAdvanced = isAdvanced
        self.searchableItems = searchableItems
        self.viewBuilder = viewBuilder
    }
}

// MARK: - Searchable Setting Item

struct SearchableSettingItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let keywords: [String]

    init(title: String, description: String, keywords: [String]) {
        self.id = UUID().uuidString
        self.title = title
        self.description = description
        self.keywords = keywords
    }

    func matches(query: String) -> Bool {
        let q = query.lowercased()
        return title.lowercased().contains(q) ||
               description.lowercased().contains(q) ||
               keywords.contains { $0.lowercased().contains(q) }
    }
}

// MARK: - Resolved Structures

/// A subcategory assembled from entries that share the same subcategory ID within a category.
struct ResolvedSubcategory {
    let id: String
    let title: String
    let icon: String
    let order: Int
    let entries: [SettingsEntry]
}

/// A category assembled from all entries that share the same category ID.
struct ResolvedCategory {
    let id: String
    let title: String
    let icon: String
    let order: Int
    /// Entries that have no subcategory (rendered directly)
    let topLevelEntries: [SettingsEntry]
    /// Subcategories with their entries (rendered behind a segmented picker)
    let subcategories: [ResolvedSubcategory]

    /// Whether this category uses subcategories
    var hasSubcategories: Bool { !subcategories.isEmpty }

    /// All searchable items across everything in this category
    var allSearchableItems: [SearchableSettingItem] {
        let topLevel = topLevelEntries.flatMap(\.searchableItems)
        let sub = subcategories.flatMap { $0.entries.flatMap(\.searchableItems) }
        return topLevel + sub
    }
}

// MARK: - Settings Category Registry

/// Central registry. Collects entries, auto-groups by category and subcategory.
class SettingsCategoryRegistry: ObservableObject {
    static let shared = SettingsCategoryRegistry()

    @Published private(set) var entries: [SettingsEntry] = []

    private init() {}

    // MARK: - Registration

    func register(_ provider: any SettingsProvider) {
        entries.append(contentsOf: provider.settingsEntries)
    }

    func register(entry: SettingsEntry) {
        entries.append(entry)
    }

    func clear() {
        entries.removeAll()
    }

    // MARK: - Resolved Categories

    var categories: [ResolvedCategory] {
        // Group entries by category ID
        var grouped: [String: (descriptor: SettingsCategoryDescriptor, entries: [SettingsEntry])] = [:]

        for entry in entries {
            let catId = entry.category.id
            if var existing = grouped[catId] {
                existing.entries.append(entry)
                if entry.category.order < existing.descriptor.order {
                    existing.descriptor = entry.category
                }
                grouped[catId] = existing
            } else {
                grouped[catId] = (entry.category, [entry])
            }
        }

        return grouped.values.map { info in
            // Separate top-level entries from subcategorized entries
            let topLevel = info.entries
                .filter { $0.subcategory == nil }
                .sorted { $0.order < $1.order }

            let subcategorized = info.entries.filter { $0.subcategory != nil }

            // Group subcategorized entries by subcategory ID
            var subGrouped: [String: (descriptor: SettingsSubcategoryDescriptor, entries: [SettingsEntry])] = [:]
            for entry in subcategorized {
                guard let sub = entry.subcategory else { continue }
                if var existing = subGrouped[sub.id] {
                    existing.entries.append(entry)
                    if sub.order < existing.descriptor.order {
                        existing.descriptor = sub
                    }
                    subGrouped[sub.id] = existing
                } else {
                    subGrouped[sub.id] = (sub, [entry])
                }
            }

            let subs = subGrouped.values
                .map { subInfo in
                    ResolvedSubcategory(
                        id: subInfo.descriptor.id,
                        title: subInfo.descriptor.title,
                        icon: subInfo.descriptor.icon,
                        order: subInfo.descriptor.order,
                        entries: subInfo.entries.sorted { $0.order < $1.order }
                    )
                }
                .sorted { $0.order < $1.order }

            return ResolvedCategory(
                id: info.descriptor.id,
                title: info.descriptor.title,
                icon: info.descriptor.icon,
                order: info.descriptor.order,
                topLevelEntries: topLevel,
                subcategories: subs
            )
        }
        .sorted { $0.order < $1.order }
    }

    func category(id: String) -> ResolvedCategory? {
        categories.first { $0.id == id }
    }

    // MARK: - Search

    private var allSearchableItems: [(categoryId: String, categoryTitle: String, item: SearchableSettingItem)] {
        categories.flatMap { cat in
            cat.allSearchableItems.map { (cat.id, cat.title, $0) }
        }
    }

    func matchingCategoryIds(for query: String) -> Set<String> {
        guard !query.isEmpty else { return Set(categories.map(\.id)) }
        var result = Set<String>()
        for (catId, catTitle, item) in allSearchableItems {
            if catTitle.lowercased().contains(query.lowercased()) || item.matches(query: query) {
                result.insert(catId)
            }
        }
        return result
    }

    func searchResults(for query: String) -> [(categoryId: String, categoryTitle: String, item: SearchableSettingItem)] {
        guard !query.isEmpty else { return [] }
        return allSearchableItems.filter { $0.item.matches(query: query) }
    }
}
