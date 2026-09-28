import Cocoa

class WorkspacesTab {
    static func initTab() -> NSView {
        let workspaces = ListEditorView(WorkspacesTableView(WorkspacesTableView.columns), 500, 150)
        let groups = ListEditorView(GroupsTableView(GroupsTableView.columns), 500, 200)
        let workspacesTable = TableGroupView(title: NSLocalizedString("Workspaces", comment: ""),
            subTitle: NSLocalizedString("Assign windows to workspaces in the Windows tab. Switch workspace from the menu bar icon.", comment: ""),
            width: PreferencesWindow.width)
        _ = workspacesTable.addRow(leftViews: [workspaces], secondaryViews: [editButtons(workspaces)])
        let groupsTable = TableGroupView(title: NSLocalizedString("Groups", comment: ""),
            subTitle: NSLocalizedString("Each group is a column of the switcher, in this order. Apps: bundle ID prefixes or app names, comma-separated. Other apps go to Ungrouped. No groups: no columns.", comment: ""),
            width: PreferencesWindow.width)
        _ = groupsTable.addRow(leftViews: [groups], secondaryViews: [editButtons(groups)])
        let view = TableGroupSetView(originalViews: [workspacesTable, groupsTable])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }

    private static func editButtons(_ editor: ListEditorView) -> NSSegmentedControl {
        let segmented = NSSegmentedControl()
        segmented.segmentCount = 4
        segmented.trackingMode = .momentary
        segmented.setImage(NSImage(named: NSImage.addTemplateName)!, forSegment: 0)
        segmented.setImage(NSImage(named: NSImage.removeTemplateName)!, forSegment: 1)
        segmented.setLabel("↑", forSegment: 2)
        segmented.setLabel("↓", forSegment: 3)
        segmented.onAction = {
            let tableView = editor.documentView as! ListEditorTableView
            switch ($0 as! NSSegmentedControl).selectedSegment {
                case 0: tableView.insertRow()
                case 1: tableView.removeSelectedRows()
                case 2: tableView.moveSelectedRow(by: -1)
                case 3: tableView.moveSelectedRow(by: 1)
                default: break
            }
        }
        return segmented
    }
}

class ListEditorView: NSScrollView {
    convenience init(_ tableView: ListEditorTableView, _ width: CGFloat, _ height: CGFloat) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        borderType = .bezelBorder
        hasVerticalScroller = true
        documentView = tableView
        fit(width, height)
    }
}

/// a table of text columns, edited in place; subclasses map rows to their preference
class ListEditorTableView: NSTableView {
    var rowCount: Int { 0 }
    func appendItem() {}
    func removeItem(_ row: Int) {}
    func moveItem(_ source: Int, _ dest: Int) {}
    func value(_ row: Int, _ colId: String) -> String { "" }
    func setValue(_ row: Int, _ colId: String, _ value: String) {}
    func save() {}

    convenience init(_ columns: [(String, CGFloat)]) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        delegate = self
        dataSource = self
        usesAlternatingRowBackgroundColors = true
        intercellSpacing = NSSize(width: 10, height: 5)
        allowsColumnReordering = false
        allowsEmptySelection = false
        allowsMultipleSelection = true
        rowSizeStyle = .medium
        columns.enumerated().forEach { (i, column) in
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(i + 1)"))
            tableColumn.headerToolTip = column.0
            tableColumn.headerCell = TableHeaderCell(column.0)
            tableColumn.width = column.1
            addTableColumn(tableColumn)
        }
        reloadData()
    }

    func insertRow() {
        appendItem()
        insertRows(at: [numberOfRows])
        save()
    }

    func removeSelectedRows() {
        if numberOfSelectedRows > 0 {
            for selectedRowIndex in selectedRowIndexes.reversed() {
                removeItem(selectedRowIndex)
            }
            removeRows(at: selectedRowIndexes)
            save()
        }
    }

    func moveSelectedRow(by step: Int) {
        guard numberOfSelectedRows == 1, let source = selectedRowIndexes.first else { return }
        let dest = source + step
        guard dest >= 0 && dest < rowCount else { return }
        moveItem(source, dest)
        beginUpdates()
        moveRow(at: source, to: dest)
        endUpdates()
        selectRowIndexes(IndexSet(integer: dest), byExtendingSelection: false)
        save()
    }

    private func text(_ value: String, _ colId: String) -> NSView {
        let text = TextField(value)
        text.isEditable = true
        text.allowsExpansionToolTips = true
        text.drawsBackground = false
        text.isBordered = false
        text.lineBreakMode = .byTruncatingTail
        text.usesSingleLineMode = true
        text.cell!.sendsActionOnEndEditing = true
        text.onAction = { [weak self] control in
            guard let self else { return }
            let row = self.row(for: control)
            guard row >= 0 && row < self.rowCount else { return }
            self.setValue(row, colId, (control as! NSTextField).stringValue)
            self.save()
        }
        let parent = NSView()
        parent.addSubview(text)
        text.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        text.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        return parent
    }
}

extension ListEditorTableView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return rowCount
    }
}

extension ListEditorTableView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let colId = tableColumn!.identifier.rawValue
        return text(value(row, colId), colId)
    }
}

class WorkspacesTableView: ListEditorTableView {
    static let columns = [(NSLocalizedString("Name", comment: ""), CGFloat(460))]
    var items = Preferences.workspaces

    override var rowCount: Int { items.count }

    override func appendItem() {
        items.append(WorkspaceEntry(id: UUID().uuidString, name: String(format: NSLocalizedString("Workspace %d", comment: ""), items.count + 1)))
    }

    override func removeItem(_ row: Int) { items.remove(at: row) }

    override func moveItem(_ source: Int, _ dest: Int) { items.insert(items.remove(at: source), at: dest) }

    override func value(_ row: Int, _ colId: String) -> String { items[row].name }

    override func setValue(_ row: Int, _ colId: String, _ value: String) { items[row].name = value }

    override func save() {
        Preferences.set("workspaces", items)
        Menubar.refreshTitle()
    }
}

class GroupsTableView: ListEditorTableView {
    static let columns = [(NSLocalizedString("Name", comment: ""), CGFloat(110)), (NSLocalizedString("Apps", comment: ""), CGFloat(340))]
    var items = Preferences.groups

    override var rowCount: Int { items.count }

    override func appendItem() {
        items.append(GroupEntry(name: String(format: NSLocalizedString("Group %d", comment: ""), items.count + 1), apps: []))
    }

    override func removeItem(_ row: Int) { items.remove(at: row) }

    override func moveItem(_ source: Int, _ dest: Int) { items.insert(items.remove(at: source), at: dest) }

    override func value(_ row: Int, _ colId: String) -> String {
        return colId == "col1" ? items[row].name : items[row].apps.joined(separator: ", ")
    }

    override func setValue(_ row: Int, _ colId: String, _ value: String) {
        if colId == "col1" {
            items[row].name = value
        } else {
            items[row].apps = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }

    override func save() {
        Preferences.set("groups", items)
    }
}
