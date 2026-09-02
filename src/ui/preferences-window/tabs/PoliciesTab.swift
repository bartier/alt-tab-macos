import Cocoa

class PoliciesTab {
    static var crashPolicyDropdown: NSPopUpButton!

    static func initTab() -> NSView {
        PoliciesTab.crashPolicyDropdown = LabelAndControl.makeDropdown("crashPolicy", CrashPolicyPreference.allCases)
        let table = TableGroupView(width: PreferencesWindow.width)
        table.addRow(leftText: NSLocalizedString("Crash reports policy", comment: ""), rightViews: [PoliciesTab.crashPolicyDropdown])
        table.fit()
        let view = TableGroupSetView(originalViews: [table])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }
}
