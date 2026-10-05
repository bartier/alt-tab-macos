import Cocoa

/// the Custom Order: the order the user dragged windows into in the switcher, and the way back to Alphabetical Order
class OrderTab {
    private static let tableView = CustomOrderTableView()
    private static let usedBy = NSTextField(labelWithString: "")

    static func initTab() -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        scrollView.fit(500, 420)
        usedBy.textColor = .secondaryLabelColor
        usedBy.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let reset = NSButton(title: NSLocalizedString("Reset to Alphabetical Order", comment: ""), target: nil, action: nil)
        reset.onAction = { _ in
            CustomOrder.reset()
            reload()
        }
        let table = TableGroupView(title: NSLocalizedString("Custom Order", comment: ""),
            subTitle: NSLocalizedString("In lists ordered alphabetically, hold or drag a window in the switcher to move it. Windows dragged into place come first, in this order; the others follow alphabetically. Dimmed: not open.", comment: ""),
            width: PreferencesWindow.width)
        _ = table.addRow(leftViews: [scrollView], secondaryViews: [reset, usedBy])
        let view = TableGroupSetView(originalViews: [table])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }

    static func reload() {
        let shortcuts = BlacklistEntry.allShortcuts.filter { CustomOrder.isEnabled($0) }.map { String($0 + 1) }
        usedBy.stringValue = shortcuts.isEmpty
            ? NSLocalizedString("No shortcut is ordered alphabetically (Preferences › Controls), so this order isn't used.", comment: "")
            : String(format: NSLocalizedString("Used by shortcut %@.", comment: ""), shortcuts.joined(separator: ", "))
        tableView.reload()
    }
}

class CustomOrderTableView: NSTableView {
    private enum Row {
        case group(String)
        case entry(CustomOrderEntry, isOpen: Bool)
        case empty
    }

    private var rows = [Row]()
    private var appNames = [String: String]()
    private var appIcons = [String: NSImage]()

    convenience init() {
        self.init(frame: .zero)
        delegate = self
        dataSource = self
        headerView = nil
        usesAlternatingRowBackgroundColors = true
        intercellSpacing = NSSize(width: 6, height: 4)
        allowsEmptySelection = true
        rowSizeStyle = .medium
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        column.width = 480
        addTableColumn(column)
    }

    func reload() {
        let entries = CustomOrder.entries
        let open = Set(Windows.list.filter { !$0.isWindowlessApp }.map { CustomOrder.entry($0) })
        // like the switcher: one section per Group (column), each in the Custom Order
        let groups = Preferences.groups
        let names = WindowGroups.columnNames
        var sections = names.map { _ in [CustomOrderEntry]() }
        for entry in entries {
            let column = groups.firstIndex { $0.contains(entry.app, appName(entry.app)) } ?? groups.count
            sections[column].append(entry)
        }
        rows = []
        for (i, section) in sections.enumerated() where !section.isEmpty {
            if WindowGroups.isEnabled { rows.append(.group(names[i])) }
            rows += section.map { .entry($0, isOpen: open.contains($0)) }
        }
        if rows.isEmpty { rows = [.empty] }
        reloadData()
    }

    fileprivate func appName(_ app: String) -> String {
        if let name = appNames[app] { return name }
        let name = Applications.list.first { $0.bundleIdentifier == app }?.displayName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? app
        appNames[app] = name
        return name
    }

    fileprivate func appIcon(_ app: String) -> NSImage? {
        if let icon = appIcons[app] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[app] = icon
        return icon
    }

    fileprivate func entryCell(_ entry: CustomOrderEntry, _ isOpen: Bool) -> NSView {
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = appIcon(entry.app)
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let name = appName(entry.app)
        let label = NSTextField(labelWithString: entry.title.isEmpty || entry.title == name ? name : "\(name) — \(entry.title)")
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = label.stringValue
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alphaValue = isOpen ? 1 : 0.5
        return stack
    }
}

extension CustomOrderTableView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }
}

extension CustomOrderTableView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .group = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
            case .group(let name):
                let label = NSTextField(labelWithString: name)
                label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
                return label
            case .entry(let entry, let isOpen):
                return entryCell(entry, isOpen)
            case .empty:
                let label = NSTextField(labelWithString: NSLocalizedString("No custom order: windows are in alphabetical order.", comment: ""))
                label.textColor = .secondaryLabelColor
                return label
        }
    }
}
