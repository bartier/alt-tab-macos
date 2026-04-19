import Cocoa

class TitleOverridesView: NSScrollView {
    convenience init() {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        borderType = .bezelBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
        documentView = TitleOverridesTableView(nil)
        fit(500, 378)
    }
}

class TitleOverridesTableView: NSTableView {
    var items = Preferences.titleOverrides

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
            NSLocalizedString("App (BundleID starting with)", comment: ""),
            NSLocalizedString("Match type", comment: ""),
            NSLocalizedString("Title pattern", comment: ""),
            NSLocalizedString("Display as", comment: ""),
        ])
        reloadData()
    }

    func insertRow() {
        items.append(TitleOverrideEntry(bundleIdentifier: "", matchType: .contains, pattern: "", replacement: ""))
        insertRows(at: [numberOfRows])
        savePreferences()
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

    private func addHeaders(_ columnHeaders: [String]) {
        let widths: [CGFloat] = [140, 90, 120, 120]
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
            case "col1": items[row].bundleIdentifier = LabelAndControl.getControlValue(control, nil) ?? ""
            case "col2": items[row].matchType = TitleOverrideMatchType.allCases[Int(LabelAndControl.getControlValue(control, nil)!)!]
            case "col3": items[row].pattern = LabelAndControl.getControlValue(control, nil) ?? ""
            case "col4": items[row].replacement = LabelAndControl.getControlValue(control, nil) ?? ""
            default: break
        }
        savePreferences()
    }

    private func savePreferences() {
        Preferences.set("titleOverrides", items)
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
        text.onAction = { self.wasUpdated(colId, $0) }
        let parent = NSView()
        parent.addSubview(text)
        text.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        text.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        return parent
    }

    private func matchTypeDropdown(_ item: TitleOverrideEntry, _ colId: String) -> NSView {
        let button = NSPopUpButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.allowsExpansionToolTips = true
        button.lineBreakMode = .byTruncatingTail
        button.addItems(withTitles: TitleOverrideMatchType.allCases.map { $0.localizedString })
        button.selectItem(at: TitleOverrideMatchType.allCases.firstIndex(of: item.matchType) ?? 0)
        button.onAction = { self.wasUpdated(colId, $0) }
        let parent = NSView()
        parent.addSubview(button)
        button.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        button.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        return parent
    }
}

extension TitleOverridesTableView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }
}

extension TitleOverridesTableView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let colId = tableColumn!.identifier.rawValue
        switch colId {
            case "col1": return text(item.bundleIdentifier, colId)
            case "col2": return matchTypeDropdown(item, colId)
            case "col3": return text(item.pattern, colId)
            case "col4": return text(item.replacement, colId)
            default: return nil
        }
    }
}
