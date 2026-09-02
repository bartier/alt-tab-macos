import Cocoa

class TitleOverridesTab {
    static func initTab() -> NSView {
        let overrides = TitleOverridesView()
        let groups = WindowGroupsView()
        (groups.documentView as! WindowGroupsTableView).onChange = {
            (overrides.documentView as! TitleOverridesTableView).reloadFromPreferences()
        }
        let groupsSegmented = NSSegmentedControl()
        groupsSegmented.segmentCount = 4
        groupsSegmented.trackingMode = .momentary
        groupsSegmented.setImage(NSImage(named: NSImage.addTemplateName)!, forSegment: 0)
        groupsSegmented.setImage(NSImage(named: NSImage.removeTemplateName)!, forSegment: 1)
        groupsSegmented.setLabel("↑", forSegment: 2)
        groupsSegmented.setLabel("↓", forSegment: 3)
        groupsSegmented.onAction = {
            let tableView = groups.documentView as! WindowGroupsTableView
            switch ($0 as! NSSegmentedControl).selectedSegment {
                case 0: tableView.insertRow()
                case 1: tableView.removeSelectedRows()
                case 2: tableView.moveSelectedRow(by: -1)
                case 3: tableView.moveSelectedRow(by: 1)
                default: break
            }
        }
        let segmented = NSSegmentedControl()
        segmented.segmentCount = 4
        segmented.trackingMode = .momentary
        segmented.setImage(NSImage(named: NSImage.addTemplateName)!, forSegment: 0)
        segmented.setImage(NSImage(named: NSImage.removeTemplateName)!, forSegment: 1)
        segmented.setLabel("↑", forSegment: 2)
        segmented.setLabel("↓", forSegment: 3)
        segmented.onAction = {
            let tableView = overrides.documentView as! TitleOverridesTableView
            switch ($0 as! NSSegmentedControl).selectedSegment {
                case 0: tableView.insertRow()
                case 1: tableView.removeSelectedRows()
                case 2: tableView.moveSelectedRow(by: -1)
                case 3: tableView.moveSelectedRow(by: 1)
                default: break
            }
        }
        let groupsTable = TableGroupView(title: NSLocalizedString("Groups", comment: ""), subTitle: NSLocalizedString("Row order is the Group rank used to order windows of the same app. Pick a Group on a title row below to assign windows to it.", comment: ""), width: PreferencesWindow.width)
        _ = groupsTable.addRow(leftViews: [groups], secondaryViews: [groupsSegmented])
        let table = TableGroupView(title: NSLocalizedString("Window titles", comment: ""), width: PreferencesWindow.width)
        _ = table.addRow(leftViews: [overrides], secondaryViews: [segmented])
        let view = TableGroupSetView(originalViews: [groupsTable, table])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }
}
