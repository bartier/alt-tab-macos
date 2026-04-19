import Cocoa

class TitleOverridesTab {
    static func initTab() -> NSView {
        let overrides = TitleOverridesView()
        let add = NSSegmentedControl(images: [NSImage(named: NSImage.addTemplateName)!, NSImage(named: NSImage.removeTemplateName)!], trackingMode: .momentary, target: nil, action: nil)
        add.onAction = {
            let tableView = overrides.documentView as! TitleOverridesTableView
            if ($0 as! NSSegmentedControl).selectedSegment == 0 {
                tableView.insertRow()
            } else {
                tableView.removeSelectedRows()
            }
        }
        let table = TableGroupView(width: PreferencesWindow.width)
        _ = table.addRow(leftViews: [overrides], secondaryViews: [add])
        let view = TableGroupSetView(originalViews: [table])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }
}
