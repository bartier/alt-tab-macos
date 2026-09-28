import Cocoa

/// every open window, and the Workspaces it belongs to; the place to fix what joined the wrong Workspace
class WindowsTab {
    private static let tableView = WindowMembershipTableView()

    static func initTab() -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        scrollView.fit(500, 420)
        let refresh = NSButton(title: NSLocalizedString("Refresh", comment: ""), target: nil, action: nil)
        refresh.onAction = { _ in reload() }
        let table = TableGroupView(title: NSLocalizedString("Windows", comment: ""),
            subTitle: NSLocalizedString("Open windows, grouped like the switcher. Tick the workspaces each window belongs to. Dimmed: in no workspace.", comment: ""),
            width: PreferencesWindow.width)
        _ = table.addRow(leftViews: [scrollView], secondaryViews: [refresh])
        let view = TableGroupSetView(originalViews: [table])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }

    static func reload() {
        tableView.reload()
    }
}

class WindowMembershipTableView: NSTableView {
    private enum Row {
        case group(String)
        case window(CGWindowID)
    }

    private var rows = [Row]()
    private var workspaces = [WorkspaceEntry]()
    private static let windowColumnId = NSUserInterfaceItemIdentifier("window")

    convenience init() {
        self.init(frame: .zero)
        delegate = self
        dataSource = self
        usesAlternatingRowBackgroundColors = true
        intercellSpacing = NSSize(width: 6, height: 4)
        allowsColumnReordering = false
        allowsEmptySelection = true
        rowSizeStyle = .medium
    }

    func reload() {
        workspaces = Preferences.workspaces
        rebuildColumns()
        let windows = Windows.list
            .filter { !$0.isWindowlessApp && $0.application.bundleIdentifier != App.bundleIdentifier }
            .sorted {
                let (c0, c1) = (WindowGroups.columnIndex($0), WindowGroups.columnIndex($1))
                if c0 != c1 { return c0 < c1 }
                let appOrder = $0.application.displayName.localizedStandardCompare($1.application.displayName)
                if appOrder != .orderedSame { return appOrder == .orderedAscending }
                return $0.displayTitle().localizedStandardCompare($1.displayTitle()) == .orderedAscending
            }
        let names = WindowGroups.columnNames
        rows = []
        var lastColumn = -1
        for window in windows {
            let column = WindowGroups.columnIndex(window)
            if column != lastColumn {
                rows.append(.group(names[column]))
                lastColumn = column
            }
            rows.append(.window(window.cgWindowId!))
        }
        reloadData()
    }

    private func rebuildColumns() {
        tableColumns.forEach { removeTableColumn($0) }
        let checkboxWidth = CGFloat(44)
        let windowColumn = NSTableColumn(identifier: WindowMembershipTableView.windowColumnId)
        windowColumn.headerCell = TableHeaderCell(NSLocalizedString("Window", comment: ""))
        windowColumn.width = max(200, 490 - CGFloat(workspaces.count) * (checkboxWidth + intercellSpacing.width))
        addTableColumn(windowColumn)
        for workspace in workspaces {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(workspace.id))
            column.headerCell = TableHeaderCell(workspace.name)
            column.headerToolTip = workspace.name
            column.width = checkboxWidth
            addTableColumn(column)
        }
    }

    fileprivate func findWindow(_ wid: CGWindowID) -> Window? {
        return Windows.list.first { $0.cgWindowId == wid }
    }

    fileprivate func windowCell(_ window: Window) -> NSView {
        let isUnassigned = Workspaces.isUnassigned(window)
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        if let cgIcon = window.icon {
            icon.image = NSImage(cgImage: cgIcon, size: NSSize(width: 16, height: 16))
        }
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let label = NSTextField(labelWithString: window.displayTitle())
        label.lineBreakMode = .byTruncatingTail
        label.textColor = isUnassigned ? .secondaryLabelColor : .labelColor
        label.toolTip = "\(window.application.displayName): \(window.title ?? "")"
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alphaValue = isUnassigned ? 0.6 : 1
        return stack
    }

    fileprivate func checkbox(_ window: Window, _ workspaceId: String) -> NSView {
        let wid = window.cgWindowId!
        let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        checkbox.state = Workspaces.workspaceIds(window).contains(workspaceId) ? .on : .off
        checkbox.onAction = { [weak self] control in
            guard let self, let window = self.findWindow(wid) else { return }
            Workspaces.setMembership(window, workspaceId, (control as! NSButton).state == .on)
            self.reload()
        }
        let parent = NSView()
        parent.addSubview(checkbox)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.centerXAnchor.constraint(equalTo: parent.centerXAnchor).isActive = true
        checkbox.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        return parent
    }
}

extension WindowMembershipTableView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }
}

extension WindowMembershipTableView: NSTableViewDelegate {
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
            case .window(let wid):
                guard let window = findWindow(wid), let tableColumn else { return nil }
                if tableColumn.identifier == WindowMembershipTableView.windowColumnId {
                    return windowCell(window)
                }
                return checkbox(window, tableColumn.identifier.rawValue)
        }
    }
}
