import Cocoa

class WindowGroupsView: NSScrollView {
    convenience init() {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        borderType = .bezelBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
        documentView = WindowGroupsTableView(nil)
        fit(500, 140)
    }
}

/// the ordered list of Groups: name, colour, and whether the Group stays visible during a Sharing session.
/// Row order is the Group rank used to order windows of the same app
class WindowGroupsTableView: NSTableView {
    var items = Preferences.windowGroups
    /// called after any change, so dependent UI (e.g. the Group column of the title overrides) can refresh
    var onChange: (() -> Void)?

    convenience init(_: Int?) {
        self.init()
        translatesAutoresizingMaskIntoConstraints = false
        delegate = self
        dataSource = self
        usesAlternatingRowBackgroundColors = true
        intercellSpacing = NSSize(width: 10, height: 5)
        allowsColumnReordering = false
        allowsEmptySelection = false
        allowsMultipleSelection = false
        rowSizeStyle = .medium
        addHeaders([
            NSLocalizedString("Group", comment: ""),
            NSLocalizedString("Colour", comment: ""),
            NSLocalizedString("Always visible while sharing", comment: ""),
        ])
        reloadData()
    }

    func insertRow() {
        items.append(WindowGroup(name: NSLocalizedString("New group", comment: ""), color: WindowGroupsTableView.nextColor()))
        insertRows(at: [numberOfRows])
        savePreferences()
    }

    func removeSelectedRows() {
        guard numberOfSelectedRows > 0 else { return }
        let removedIds = selectedRowIndexes.map { items[$0].id }
        for selectedRowIndex in selectedRowIndexes.reversed() {
            items.remove(at: selectedRowIndex)
        }
        removeRows(at: selectedRowIndexes)
        // rows that pointed at a deleted Group fall back to no Group
        let overrides = Preferences.titleOverrides.map { entry -> TitleOverrideEntry in
            var e = entry
            if let id = e.groupId, removedIds.contains(id) { e.groupId = nil }
            return e
        }
        Preferences.set("titleOverrides", overrides)
        if removedIds.contains(Preferences.sharingWithGroup) {
            Preferences.set("sharingWithGroup", "")
            Menubar.applySharingState()
        }
        savePreferences()
    }

    func moveSelectedRow(by step: Int) {
        guard numberOfSelectedRows == 1, let source = selectedRowIndexes.first else { return }
        let dest = source + step
        guard dest >= 0 && dest < items.count else { return }
        let moved = items.remove(at: source)
        items.insert(moved, at: dest)
        beginUpdates()
        moveRow(at: source, to: dest)
        endUpdates()
        selectRowIndexes(IndexSet(integer: dest), byExtendingSelection: false)
        savePreferences()
    }

    private static let palette = ["#8e8e93", "#34c759", "#ff9500", "#af52de", "#007aff", "#ff2d55", "#5ac8fa", "#ffcc00"]

    private static func nextColor() -> String {
        let used = Set(Preferences.windowGroups.map { $0.color.lowercased() })
        return palette.first { !used.contains($0) } ?? palette[Preferences.windowGroups.count % palette.count]
    }

    private func addHeaders(_ columnHeaders: [String]) {
        let widths: [CGFloat] = [180, 60, 200]
        columnHeaders.enumerated().forEach { (i, header: String) in
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(i + 1)"))
            column.headerToolTip = header
            column.headerCell = TableHeaderCell(header)
            column.width = widths[i]
            addTableColumn(column)
        }
    }

    private func wasUpdated(_ colId: String, _ control: NSControl) {
        let row = row(for: control)
        guard row >= 0 && row < items.count else { return }
        switch colId {
            case "col1": items[row].name = LabelAndControl.getControlValue(control, nil) ?? ""
            case "col2": items[row].color = (control as! NSColorWell).color.windowGroupHex
            case "col3": items[row].alwaysVisibleWhileSharing = (control as! NSButton).state == .on
            default: break
        }
        savePreferences()
    }

    private func savePreferences() {
        Preferences.set("windowGroups", items)
        Menubar.applySharingState()
        onChange?()
    }

    private func text(_ value: String, _ colId: String) -> NSView {
        let text = TextField(value)
        text.isEditable = true
        text.drawsBackground = false
        text.isBordered = false
        text.lineBreakMode = .byTruncatingTail
        text.usesSingleLineMode = true
        text.cell!.sendsActionOnEndEditing = true
        text.onAction = { self.wasUpdated(colId, $0) }
        let parent = NSView()
        parent.addSubview(text)
        text.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        text.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        return parent
    }

    private func colorWell(_ item: WindowGroup, _ colId: String) -> NSView {
        let well = NSColorWell()
        well.translatesAutoresizingMaskIntoConstraints = false
        well.color = NSColor(windowGroupHex: item.color) ?? .gray
        well.onAction = { self.wasUpdated(colId, $0) }
        let parent = NSView()
        parent.addSubview(well)
        well.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        well.centerXAnchor.constraint(equalTo: parent.centerXAnchor).isActive = true
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return parent
    }

    private func checkbox(_ item: WindowGroup, _ colId: String) -> NSView {
        let box = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.state = item.alwaysVisibleWhileSharing ? .on : .off
        box.onAction = { self.wasUpdated(colId, $0) }
        let parent = NSView()
        parent.addSubview(box)
        box.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        box.centerXAnchor.constraint(equalTo: parent.centerXAnchor).isActive = true
        return parent
    }
}

extension WindowGroupsTableView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }
}

extension WindowGroupsTableView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let colId = tableColumn!.identifier.rawValue
        switch colId {
            case "col1": return text(item.name, colId)
            case "col2": return colorWell(item, colId)
            case "col3": return checkbox(item, colId)
            default: return nil
        }
    }
}
