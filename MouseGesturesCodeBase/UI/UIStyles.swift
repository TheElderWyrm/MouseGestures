import SwiftUI
import AppKit

// MARK: - Unified Style Constants

/// Central namespace for all UI style constants used throughout the app.
/// All views should reference these values instead of using hardcoded numbers.
enum MGStyle {

    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
    }

    // MARK: Corner Radii
    enum Corner {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 10
    }

    // MARK: Font Sizes
    enum FontSize {
        static let badge: CGFloat = 10
        static let caption: CGFloat = 11
        static let body: CGFloat = 13
        static let heading: CGFloat = 14
    }

    // MARK: Icon Sizes
    enum IconSize {
        static let inline: CGFloat = 11
        static let row: CGFloat = 13
        static let emptyState: CGFloat = 48
    }

    // MARK: Colors
    enum Colors {
        static var cardBackground: Color { Color(NSColor.controlBackgroundColor) }
        static var contentBackground: Color { Color(NSColor.textBackgroundColor) }
        static var windowBackground: Color { Color(NSColor.windowBackgroundColor) }
        static var separator: Color { Color(NSColor.separatorColor) }
        static var selectedRow: Color { Color.accentColor.opacity(0.2) }
        static var hoveredRow: Color { Color(NSColor.controlBackgroundColor) }
        static var subtleOverlay: Color { Color(NSColor.controlBackgroundColor).opacity(0.5) }
    }

    // MARK: Layout
    enum Layout {
        static let searchFieldWidth: CGFloat = 200
        static let sidebarMinWidth: CGFloat = 200
        static let sidebarIdealWidth: CGFloat = 250
        static let sidebarMaxWidth: CGFloat = 300
        static let listMinWidth: CGFloat = 300
        static let listIdealWidth: CGFloat = 400
        static let detailMinWidth: CGFloat = 300
    }
}

// MARK: - Unified Search Field

/// Consistent search field used across all views.
struct MGSearchField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String = "Search...", text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        HStack(spacing: MGStyle.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: MGStyle.FontSize.body))
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: MGStyle.IconSize.inline))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(MGStyle.Spacing.md)
        .background(MGStyle.Colors.cardBackground)
        .cornerRadius(MGStyle.Corner.md)
        .overlay(
            RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                .stroke(MGStyle.Colors.separator, lineWidth: 0.5)
        )
    }
}

// MARK: - Unified Page Header

/// Consistent page header for top-level tab views.
struct MGPageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let actions: () -> Actions

    init(_ title: String, subtitle: String? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: MGStyle.Spacing.lg) {
                actions()
            }
        }
        .padding(MGStyle.Spacing.xl)
    }
}

// MARK: - Unified Sheet Header

/// Consistent header for sheet/modal views.
struct MGSheetHeader: View {
    let title: String
    let subtitle: String?
    let onCancel: (() -> Void)?

    init(_ title: String, subtitle: String? = nil, onCancel: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let onCancel {
                    Button("Cancel", action: onCancel)
                }
            }
            .padding(MGStyle.Spacing.xl)

            Divider()
        }
    }
}

// MARK: - Unified Sheet Footer

/// Consistent footer for sheet/modal views.
struct MGSheetFooter<LeadingContent: View>: View {
    let primaryLabel: String
    let primaryAction: () -> Void
    let primaryDisabled: Bool
    let cancelAction: (() -> Void)?
    @ViewBuilder let leading: () -> LeadingContent

    init(
        _ primaryLabel: String,
        disabled: Bool = false,
        action: @escaping () -> Void,
        cancel: (() -> Void)? = nil,
        @ViewBuilder leading: @escaping () -> LeadingContent = { EmptyView() }
    ) {
        self.primaryLabel = primaryLabel
        self.primaryAction = action
        self.primaryDisabled = disabled
        self.cancelAction = cancel
        self.leading = leading
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                leading()

                Spacer()

                HStack(spacing: MGStyle.Spacing.md) {
                    if let cancelAction {
                        Button("Cancel", action: cancelAction)
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                    Button(primaryLabel, action: primaryAction)
                        .keyboardShortcut(.return)
                        .disabled(primaryDisabled)
                }
            }
            .padding(MGStyle.Spacing.xl)
        }
    }
}

// MARK: - Unified Content Card

/// Consistent card background used for content sections.
struct MGContentCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
            content()
        }
        .padding(MGStyle.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .fill(MGStyle.Colors.cardBackground)
        )
    }
}

// MARK: - Unified Badge

/// Consistent badge/tag used for status indicators, labels, etc.
struct MGBadge: View {
    let text: String
    let color: Color
    let icon: String?

    init(_ text: String, color: Color = .accentColor, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: MGStyle.Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: MGStyle.FontSize.badge))
            }
            Text(text)
                .font(.system(size: MGStyle.FontSize.badge))
        }
        .padding(.horizontal, MGStyle.Spacing.md)
        .padding(.vertical, MGStyle.Spacing.xs)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(MGStyle.Corner.sm)
    }
}

// MARK: - Unified Empty State

/// Consistent empty state placeholder view.
struct MGEmptyState: View {
    let icon: String
    let title: String
    let description: String?
    let actionLabel: String?
    let action: (() -> Void)?

    init(icon: String, title: String, description: String? = nil, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        VStack(spacing: MGStyle.Spacing.xl) {
            Image(systemName: icon)
                .font(.system(size: MGStyle.IconSize.emptyState))
                .foregroundColor(.secondary.opacity(0.5))

            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)

            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            if let actionLabel, let action {
                Button(action: action) {
                    Label(actionLabel, systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MGStyle.Spacing.xxl)
    }
}

// MARK: - Unified List Section Header

/// Consistent section header for list areas.
struct MGListSectionHeader: View {
    let title: String
    let count: Int?
    let trailing: AnyView?

    init(_ title: String, count: Int? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.count = count
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            HStack(spacing: MGStyle.Spacing.md) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.secondary)

                if let count {
                    Text("(\(count))")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, MGStyle.Spacing.xl)
        .padding(.vertical, MGStyle.Spacing.md)
        .background(MGStyle.Colors.subtleOverlay)
    }
}

// MARK: - Unified Sidebar

/// Consistent sidebar item for views using sidebar navigation.
struct MGSidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MGStyle.Spacing.md) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(isSelected ? .white : .secondary)
                Text(title)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Consistent sidebar container layout.
struct MGSidebar<Content: View, Header: View, Footer: View>: View {
    let title: String
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    init(
        title: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() },
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.header = header
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, MGStyle.Spacing.xxl)
                .padding(.top, MGStyle.Spacing.xxl)
                .padding(.bottom, MGStyle.Spacing.lg)

            header()

            Divider()
                .padding(.horizontal, MGStyle.Spacing.xxl)
                .padding(.bottom, MGStyle.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                    content()
                }
                .padding(.horizontal, MGStyle.Spacing.lg)
            }

            Spacer()

            footer()
        }
        .background(MGStyle.Colors.cardBackground)
    }
}

// MARK: - Unified List Row Modifiers

/// Consistent interactive list row styling with selection and hover.
struct MGListRowModifier: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool
    let showBorder: Bool

    init(isSelected: Bool, isHovered: Bool, showBorder: Bool = false) {
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.showBorder = showBorder
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, MGStyle.Spacing.lg)
            .padding(.vertical, MGStyle.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                    .fill(isSelected ? MGStyle.Colors.selectedRow :
                          (isHovered ? MGStyle.Colors.hoveredRow : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                    .stroke(
                        showBorder && isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .contentShape(Rectangle())
    }
}

extension View {
    /// Apply consistent list row styling with selection and hover states.
    func mgListRow(isSelected: Bool, isHovered: Bool, showBorder: Bool = false) -> some View {
        modifier(MGListRowModifier(isSelected: isSelected, isHovered: isHovered, showBorder: showBorder))
    }
}

// MARK: - Unified List Card

/// Consistent card styling for list items across all tabs.
/// Provides: rounded background, hover highlight, selection state, optional expand border, content shape.
struct MGListCardModifier: ViewModifier {
    let isHovered: Bool
    let isExpanded: Bool
    let isSelected: Bool

    init(isHovered: Bool, isExpanded: Bool = false, isSelected: Bool = false) {
        self.isHovered = isHovered
        self.isExpanded = isExpanded
        self.isSelected = isSelected
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                    .fill(isSelected ? MGStyle.Colors.selectedRow :
                          (isHovered ? MGStyle.Colors.cardBackground : MGStyle.Colors.cardBackground.opacity(0.6)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.35) :
                        (isExpanded ? Color.accentColor.opacity(0.3) :
                        (isHovered ? MGStyle.Colors.separator.opacity(0.4) : MGStyle.Colors.separator.opacity(0.2))),
                        lineWidth: isSelected || isExpanded ? 1 : 0.5
                    )
            )
            .contentShape(Rectangle())
    }
}

extension View {
    /// Apply unified list card styling.
    func mgListCard(isHovered: Bool, isExpanded: Bool = false, isSelected: Bool = false) -> some View {
        modifier(MGListCardModifier(isHovered: isHovered, isExpanded: isExpanded, isSelected: isSelected))
    }
}

// MARK: - Unified Action Button

/// Button with expanded hit target for better clickability.
/// Use instead of raw icon buttons for row actions.
struct MGActionButton: View {
    let icon: String
    let isDestructive: Bool
    let helpText: String
    let action: () -> Void

    init(_ icon: String, help: String = "", destructive: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.helpText = help
        self.isDestructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: MGStyle.IconSize.row))
                .foregroundColor(isDestructive ? .red.opacity(0.7) : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

// MARK: - Unified Hover Row Actions

/// Consistent inline action buttons shown on row hover, with expanded hit targets.
struct MGRowActions: View {
    struct Action {
        let icon: String
        let isDestructive: Bool
        let helpText: String
        let handler: () -> Void

        init(_ icon: String, help: String = "", destructive: Bool = false, action: @escaping () -> Void) {
            self.icon = icon
            self.helpText = help
            self.isDestructive = destructive
            self.handler = action
        }
    }

    let actions: [Action]

    var body: some View {
        HStack(spacing: MGStyle.Spacing.xs) {
            ForEach(actions.indices, id: \.self) { i in
                MGActionButton(
                    actions[i].icon,
                    help: actions[i].helpText,
                    destructive: actions[i].isDestructive,
                    action: actions[i].handler
                )
            }
        }
    }
}

// MARK: - Unified Section Header (Content Area)

/// Consistent section header for content area sections (not sidebar).
struct MGSectionHeader: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: MGStyle.Spacing.md) {
            if let icon {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Unified Divider with Spacing

struct MGHeaderDivider: View {
    var body: some View {
        Divider()
            .frame(height: 20)
    }
}

// MARK: - Visual Screen Zone Picker

/// Interactive 3×3-style grid representing screen zones.
/// Zones map to edges and corners of the screen.
struct MGZonePicker: View {
    @Binding var selected: ScreenZone

    private let rows = 3
    private let cols = 3

    // Map grid positions to zones (row, col) — center cell is nil (no zone)
    private func zone(row: Int, col: Int) -> ScreenZone? {
        switch (row, col) {
        case (0, 0): return .topLeft
        case (0, 1): return .top
        case (0, 2): return .topRight
        case (1, 0): return .left
        case (1, 1): return nil  // center of screen — no zone
        case (1, 2): return .right
        case (2, 0): return .bottomLeft
        case (2, 1): return .bottom
        case (2, 2): return .bottomRight
        default: return nil
        }
    }

    private func isCorner(row: Int, col: Int) -> Bool {
        (row == 0 || row == 2) && (col == 0 || col == 2)
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<cols, id: \.self) { col in
                        zoneCell(row: row, col: col)
                    }
                }
            }
        }
        .padding(MGStyle.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .fill(Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .stroke(MGStyle.Colors.separator, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func zoneCell(row: Int, col: Int) -> some View {
        let z = zone(row: row, col: col)
        let isSel = z == selected
        let corner = isCorner(row: row, col: col)
        let isCenter = row == 1 && col == 1

        let w: CGFloat = col == 1 ? 64 : (corner ? 36 : 36)
        let h: CGFloat = row == 1 ? 40 : (corner ? 28 : 28)

        if let z = z {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selected = z } }) {
                ZStack {
                    RoundedRectangle(cornerRadius: corner ? MGStyle.Corner.sm : MGStyle.Corner.xs)
                        .fill(isSel ? Color.accentColor : Color(NSColor.controlBackgroundColor))

                    RoundedRectangle(cornerRadius: corner ? MGStyle.Corner.sm : MGStyle.Corner.xs)
                        .stroke(isSel ? Color.accentColor : MGStyle.Colors.separator.opacity(0.6), lineWidth: isSel ? 1.5 : 0.5)

                    if isSel {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: w, height: h)
            }
            .buttonStyle(.plain)
            .help(z.displayName)
        } else {
            // Center cell — represents the screen interior
            ZStack {
                RoundedRectangle(cornerRadius: MGStyle.Corner.xs)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    .frame(width: w, height: h)
                Image(systemName: "display")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
    }
}

/// Compact inline zone indicator (non-interactive)
struct MGZoneIndicator: View {
    let zone: ScreenZone

    private func pos() -> (row: Int, col: Int) {
        switch zone {
        case .topLeft: return (0, 0)
        case .top: return (0, 1)
        case .topRight: return (0, 2)
        case .left: return (1, 0)
        case .right: return (1, 2)
        case .bottomLeft: return (2, 0)
        case .bottom: return (2, 1)
        case .bottomRight: return (2, 2)
        }
    }

    var body: some View {
        let p = pos()
        VStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { col in
                        let active = row == p.row && col == p.col
                        let isCenter = row == 1 && col == 1
                        RoundedRectangle(cornerRadius: 1)
                            .fill(active ? Color.accentColor : (isCenter ? Color.clear : Color.secondary.opacity(0.2)))
                            .frame(width: col == 1 ? 8 : 5, height: row == 1 ? 6 : 4)
                    }
                }
            }
        }
        .padding(2)
    }
}

// MARK: - Trigger Pill

/// Small inline pill showing a trigger component.
struct MGTriggerPill: View {
    let icon: String
    let text: String
    let color: Color

    init(_ text: String, icon: String, color: Color = .secondary) {
        self.text = text
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: MGStyle.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, MGStyle.Spacing.md)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(MGStyle.Corner.sm)
    }
}

// MARK: - Unified Detail Section

/// Modern detail section replacing GroupBox for detail panels.
struct MGDetailSection<Content: View>: View {
    let title: String
    let icon: String?
    let content: () -> Content

    init(_ title: String, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
            HStack(spacing: MGStyle.Spacing.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Text(title)
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                content()
            }
        }
        .padding(MGStyle.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .fill(MGStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .stroke(MGStyle.Colors.separator.opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Unified Detail Row

/// Key-value row for detail panels with consistent styling.
struct MGDetailRow: View {
    let label: String
    let value: String
    let icon: String?
    let valueColor: Color

    init(_ label: String, value: String, icon: String? = nil, valueColor: Color = .primary) {
        self.label = label
        self.value = value
        self.icon = icon
        self.valueColor = valueColor
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 14)
            }
            Text(label)
                .font(.system(size: MGStyle.FontSize.body))
                .foregroundColor(.secondary)
                .frame(minWidth: 100, alignment: .leading)
            Text(value)
                .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Unified Selection Banner

/// Shows the currently selected item prominently.
struct MGSelectionBanner: View {
    let icon: String
    let title: String
    let subtitle: String?
    let accentColor: Color

    init(icon: String, title: String, subtitle: String? = nil, accentColor: Color = .accentColor) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.accentColor = accentColor
    }

    var body: some View {
        HStack(spacing: MGStyle.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: MGStyle.FontSize.body, weight: .semibold))
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: MGStyle.FontSize.caption))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 14))
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, MGStyle.Spacing.lg)
        .padding(.vertical, MGStyle.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                .fill(accentColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Unified Toolbar (Compact Header)

/// Compact toolbar for tab headers. Primary actions on the left, secondary in overflow menu.
struct MGCompactHeader<Leading: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let leading: () -> Leading
    let menuItems: [MGMenuItem]

    init(
        _ title: String,
        subtitle: String? = nil,
        menuItems: [MGMenuItem] = [],
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.menuItems = menuItems
        self.leading = leading
    }

    var body: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            // Title area
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Primary actions
            HStack(spacing: MGStyle.Spacing.md) {
                leading()
            }

            // Overflow menu (secondary actions)
            if !menuItems.isEmpty {
                Menu {
                    ForEach(menuItems) { item in
                        if item.isDivider {
                            Divider()
                        } else {
                            Button(action: item.action ?? {}) {
                                Label(item.label, systemImage: item.icon)
                            }
                            .disabled(item.isDisabled)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
        }
        .padding(.horizontal, MGStyle.Spacing.xl)
        .padding(.vertical, MGStyle.Spacing.lg)
    }
}

/// Menu item for MGCompactHeader's overflow menu.
struct MGMenuItem: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let action: (() -> Void)?
    let isDisabled: Bool
    let isDivider: Bool
    let isDestructive: Bool

    init(_ label: String, icon: String, disabled: Bool = false, destructive: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.action = action
        self.isDisabled = disabled
        self.isDivider = false
        self.isDestructive = destructive
    }

    static var divider: MGMenuItem {
        MGMenuItem(isDivider: true)
    }

    private init(isDivider: Bool) {
        self.label = ""
        self.icon = ""
        self.action = nil
        self.isDisabled = false
        self.isDivider = true
        self.isDestructive = false
    }
}
