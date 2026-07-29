import Cocoa

class BlacklistView: NSScrollView {
    convenience init() {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        borderType = .bezelBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
        documentView = TableView(nil)
        fit(580, 378)
    }
}

class TableView: NSTableView {
    var items = Preferences.blacklist

    convenience init(_: Int?) {
        self.init()
        translatesAutoresizingMaskIntoConstraints = false
        delegate = self
        dataSource = self
        usesAlternatingRowBackgroundColors = true
        intercellSpacing = NSSize(width: 10, height: 5)
        allowsColumnReordering = false
        allowsEmptySelection = false
        allowsMultipleSelection = true
        rowSizeStyle = .medium
        addHeaders([
            (NSLocalizedString("App (BundleID starting with)", comment: ""), nil, 170),
            (String(format: NSLocalizedString("Hide in %@", comment: "%@ is AltTab"), App.name), nil, 140),
            (NSLocalizedString("For shortcuts", comment: ""),
                NSLocalizedString("Shortcuts for which the “Hide” rule applies. “4” also applies to the Gesture", comment: ""), 100),
            (NSLocalizedString("Ignore shortcuts when active", comment: ""), nil, nil),
        ])
        reloadData()
    }

    func insertRow(_ bundleId: String) {
        if !(items.contains { $0.bundleIdentifier == bundleId }) {
            items.append(BlacklistEntry(bundleIdentifier: bundleId, hide: .always, ignore: .none))
            insertRows(at: [numberOfRows])
            savePreferences()
        }
    }

    func removeSelectedRows() {
        if numberOfSelectedRows > 0 {
            for selectedRowIndex in selectedRowIndexes.reversed() {
                items.remove(at: selectedRowIndex)
            }
            removeRows(at: selectedRowIndexes)
            savePreferences()
        }
    }

    private func addHeaders(_ columnHeaders: [(String, String?, CGFloat?)]) {
        columnHeaders.enumerated().forEach { (i, header: (String, String?, CGFloat?)) in
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(i + 1)"))
            column.headerToolTip = header.1 ?? header.0
            column.headerCell = TableHeaderCell(header.0)
            if let width = header.2 {
                column.width = width
            }
            addTableColumn(column)
        }
    }

    private func wasUpdated(_ colId: String, _ control: NSControl) {
        let row = row(for: control)
        if colId == "col1" {
            items[row].bundleIdentifier = LabelAndControl.getControlValue(control, nil)!
        } else if colId == "col2" {
            items[row].hide = BlacklistHidePreference.allCases[Int(LabelAndControl.getControlValue(control, nil)!)!]
            // the scope control is only enabled when the hide rule is active
            reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 2))
        } else {
            items[row].ignore = BlacklistIgnorePreference.allCases[Int(LabelAndControl.getControlValue(control, nil)!)!]
        }
        savePreferences()
    }

    private func savePreferences() {
        Preferences.set("blacklist", items)
    }

    private func text(_ item: BlacklistEntry) -> NSView {
        let text = TextField(item.bundleIdentifier)
        text.isEditable = true
        text.allowsExpansionToolTips = true
        text.drawsBackground = false
        text.isBordered = false
        text.lineBreakMode = .byTruncatingTail
        text.usesSingleLineMode = true
        text.cell!.sendsActionOnEndEditing = true
        text.onAction = { self.wasUpdated("col1", $0) }
        let parent = NSView()
        parent.addSubview(text)
        text.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        text.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        return parent
    }

    private func dropdown(_ item: BlacklistEntry, _ colId: String) -> NSView {
        let isHidePref = colId == "col2"
        let button = NSPopUpButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.allowsExpansionToolTips = true
        button.lineBreakMode = .byTruncatingTail
        let cases: [MacroPreference] = isHidePref ? BlacklistHidePreference.allCases : BlacklistIgnorePreference.allCases
        button.addItems(withTitles: cases.map { $0.localizedString })
        button.selectItem(at: isHidePref ? item.hide.index : item.ignore.index)
        button.onAction = { self.wasUpdated(colId, $0) }
        let parent = NSView()
        parent.addSubview(button)
        button.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        button.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        return parent
    }

    private func hideInShortcutsControl(_ item: BlacklistEntry) -> NSView {
        let control = NSSegmentedControl(labels: BlacklistEntry.allShortcuts.map { String($0 + 1) }, trackingMode: .selectAny, target: nil, action: nil)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.controlSize = .small
        control.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        BlacklistEntry.allShortcuts.forEach { i in
            control.setSelected(item.hideIn.contains(i), forSegment: i)
            if #available(macOS 10.13, *) {
                control.setToolTip(i == Preferences.gestureIndex
                    ? NSLocalizedString("Shortcut 4 and Gesture", comment: "")
                    : String(format: NSLocalizedString("Shortcut %d", comment: ""), i + 1), forSegment: i)
            }
        }
        control.isEnabled = item.hide != .none
        control.onAction = { control in
            let control = control as! NSSegmentedControl
            let row = self.row(for: control)
            self.items[row].hideIn = BlacklistEntry.allShortcuts.filter { control.isSelected(forSegment: $0) }
            self.savePreferences()
        }
        let parent = NSView()
        parent.addSubview(control)
        control.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        control.centerXAnchor.constraint(equalTo: parent.centerXAnchor).isActive = true
        return parent
    }
}

extension TableView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }
}

extension TableView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        switch tableColumn!.identifier.rawValue {
            case "col1": return text(item)
            case "col3": return hideInShortcutsControl(item)
            default: return dropdown(item, tableColumn!.identifier.rawValue)
        }
    }
}

class TableHeaderCell: NSTableHeaderCell {
    convenience init(_ textCell: String) {
        self.init(textCell: textCell)
        lineBreakMode = .byTruncatingTail
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        // add some padding so the headers can breath; get closer to what Finder does
        super.drawInterior(withFrame: cellFrame.insetBy(dx: CGFloat(5), dy: CGFloat(0)), in: controlView)
    }
}
