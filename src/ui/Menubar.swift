import Cocoa

class Menubar {
    static var statusItem: NSStatusItem!
    static var menu: NSMenu!
    private static var workspaceMenuItems = [NSMenuItem]()
    private static let workspaceActions = WorkspaceMenuActions()

    static func initialize() {
        menu = NSMenu()
        menu.title = App.name // perf: prevent going through expensive code-path within appkit
        menu.addItem(
            withTitle: String(format: NSLocalizedString("About %@", comment: "Menubar option. %@ is AltTab"), App.name),
            action: #selector(App.app.showAboutTab),
            keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: NSLocalizedString("Show", comment: "Menubar option"),
            action: #selector(App.app.showUi),
            keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Preferences…", comment: "Menubar option"),
            action: #selector(App.app.showPreferencesWindow),
            keyEquivalent: ",")
        menu.addItem(
            withTitle: NSLocalizedString("Check for updates…", comment: "Menubar option"),
            action: #selector(App.app.checkForUpdatesNow),
            keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Check permissions…", comment: "Menubar option"),
            action: #selector(App.app.checkPermissions),
            keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Send feedback…", comment: "Menubar option"),
            action: #selector(App.app.showFeedbackPanel),
            keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Support this project ❤️", comment: "Menubar option"),
            action: #selector(App.app.supportProject),
            keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: String(format: NSLocalizedString("Quit %@", comment: "Menubar option. %@ is AltTab"), App.name),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.target = self
        statusItem.button!.action = #selector(statusItemOnClick)
        statusItem.button!.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @objc static func statusItemOnClick() {
        // NSApp.currentEvent == nil if the icon is "clicked" through VoiceOver
        if let type = NSApp.currentEvent?.type, type != .leftMouseDown {
            App.app.showUi()
        } else {
            rebuildWorkspaceItems()
            statusItem.popUpMenu(Menubar.menu)
        }
    }

    /// shows the active Workspace next to the icon, so the user always knows which context they're in
    static func refreshTitle() {
        guard let statusItem, let button = statusItem.button else { return }
        if let active = Workspaces.active {
            statusItem.length = NSStatusItem.variableLength
            button.title = active.name
            button.imagePosition = .imageLeft
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    /// the Workspaces section is rebuilt each time the menu opens, since Workspaces can change
    private static func rebuildWorkspaceItems() {
        workspaceMenuItems.forEach { menu.removeItem($0) }
        var items = [NSMenuItem]()
        let workspaces = Preferences.workspaces
        let activeId = Workspaces.active?.id
        let header = NSMenuItem(title: NSLocalizedString("Workspaces", comment: "Menubar section"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        items.append(header)
        for workspace in workspaces {
            items.append(workspaceActions.item(workspace.name, #selector(WorkspaceMenuActions.activate(_:)), workspace.id, workspace.id == activeId))
        }
        items.append(workspaceActions.item(NSLocalizedString("No workspace", comment: "Menubar option"), #selector(WorkspaceMenuActions.activate(_:)), nil, activeId == nil))
        items.append(workspaceActions.item(NSLocalizedString("Manage windows…", comment: "Menubar option"), #selector(WorkspaceMenuActions.manageWindows), nil, false))
        items.append(workspaceActions.item(NSLocalizedString("Manage workspaces and groups…", comment: "Menubar option"), #selector(WorkspaceMenuActions.manage), nil, false))
        items.append(NSMenuItem.separator())
        for (i, item) in items.enumerated() {
            menu.insertItem(item, at: i)
        }
        workspaceMenuItems = items
    }

    static func menubarIconCallback(_: NSControl?) {
        if Preferences.menubarIconShown {
            loadPreferredIcon()
        } else {
            statusItem.isVisible = false
        }
        if let menubarIconDropdown = GeneralTab.menubarIconDropdown {
            menubarIconDropdown.isEnabled = Preferences.menubarIconShown
        }
    }

    static private func loadPreferredIcon() {
        let i = Preferences.menubarIcon.indexAsString
        let image = NSImage(named: "menubar-\(i)")!
        image.isTemplate = i != "2"
        statusItem.button!.image = image
        statusItem.isVisible = true
        statusItem.button!.imageScaling = .scaleProportionallyUpOrDown
    }
}

class WorkspaceMenuActions: NSObject {
    func item(_ title: String, _ action: Selector, _ workspaceId: String?, _ isOn: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = workspaceId
        item.state = isOn ? .on : .off
        return item
    }

    @objc func activate(_ sender: NSMenuItem) {
        Workspaces.activate(sender.representedObject as? String)
    }

    @objc func manageWindows() {
        App.app.preferencesWindow.selectTab("windows")
        App.app.showPreferencesWindow()
    }

    @objc func manage() {
        App.app.preferencesWindow.selectTab("workspaces")
        App.app.showPreferencesWindow()
    }
}
