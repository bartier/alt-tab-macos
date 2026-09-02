import Cocoa

class Menubar {
    static var statusItem: NSStatusItem!
    static var menu: NSMenu!
    static var permissionCalloutMenuItems: [NSMenuItem]?
    static var sharingMenuItem: NSMenuItem!
    static let sharingMenuDelegate = SharingMenuDelegate()

    static func initialize() {
        menu = NSMenu()
        menu.title = App.name // perf: prevent going through expensive code-path within appkit
        let permissionCalloutMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        permissionCalloutMenuItem.view = PermissionCallout()
        let calloutSeparator = NSMenuItem.separator()
        permissionCalloutMenuItems = [permissionCalloutMenuItem, calloutSeparator]
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
        sharingMenuItem = NSMenuItem(title: NSLocalizedString("Sharing with", comment: "Menubar option"), action: nil, keyEquivalent: "")
        sharingMenuItem.submenu = NSMenu(title: "")
        sharingMenuItem.submenu!.delegate = sharingMenuDelegate
        menu.addItem(sharingMenuItem)
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

    // NSMenuItem.isHidden isn't reliable with custom views. We add/remove to hide/show these items
    static func togglePermissionCallout(_ show: Bool) {
        permissionCalloutMenuItems?.enumerated().forEach { offset, element in
            if show && !menu.items.contains(element) {
                menu.insertItem(element, at: offset)
            }
            if !show && menu.items.contains(element) {
                menu.removeItem(element)
            }
        }
    }

    @objc static func statusItemOnClick() {
        // NSApp.currentEvent == nil if the icon is "clicked" through VoiceOver
        if let type = NSApp.currentEvent?.type, type != .leftMouseDown {
            App.app.showUi()
        } else {
            statusItem.popUpMenu(Menubar.menu)
        }
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
        applySharingState()
    }

    /// while a Sharing session is on, the icon takes the shared Group's colour so a forgotten session is hard to miss
    static func applySharingState() {
        guard let button = statusItem?.button, let image = button.image else { return }
        let sharingGroup = Preferences.sharingGroup
        let i = Preferences.menubarIcon.indexAsString
        image.isTemplate = sharingGroup != nil || i != "2"
        button.image = image
        if #available(macOS 10.14, *) {
            button.contentTintColor = sharingGroup.flatMap { NSColor(windowGroupHex: $0.color) }
        }
        button.toolTip = sharingGroup.map { String(format: NSLocalizedString("Sharing with %@", comment: ""), $0.name) }
    }
}

/// builds the "Sharing with" submenu on open, so it always reflects the current Group list
class SharingMenuDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = Preferences.sharingWithGroup
        let none = NSMenuItem(title: NSLocalizedString("Not sharing", comment: "Menubar option"), action: #selector(pick(_:)), keyEquivalent: "")
        none.target = self
        none.representedObject = ""
        none.state = current.isEmpty ? .on : .off
        menu.addItem(none)
        menu.addItem(NSMenuItem.separator())
        for group in Preferences.windowGroups {
            let item = NSMenuItem(title: group.name, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = group.id
            item.state = group.id == current ? .on : .off
            item.image = NSColor(windowGroupHex: group.color).map { NSImage.windowGroupDot($0, 10) }
            menu.addItem(item)
        }
    }

    @objc func pick(_ sender: NSMenuItem) {
        let id = sender.representedObject as? String ?? ""
        guard id != Preferences.sharingWithGroup else { return }
        Logger.info("sharing session changed", id.isEmpty ? "not sharing" : sender.title)
        Preferences.set("sharingWithGroup", id)
        Menubar.applySharingState()
        if App.app.appIsBeingUsed {
            App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
        }
    }
}
