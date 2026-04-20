import Cocoa

class TitleOverridesTab {
    static func initTab() -> NSView {
        let overrides = TitleOverridesView()
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
        let table = TableGroupView(width: PreferencesWindow.width)
        _ = table.addRow(leftViews: [overrides], secondaryViews: [segmented])
        let view = TableGroupSetView(originalViews: [table])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }
}
