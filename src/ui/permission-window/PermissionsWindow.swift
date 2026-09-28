import Cocoa

class PermissionsWindow: NSWindow {
    var accessibilityView: PermissionView!

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .miniaturizable, .closable], backing: .buffered, defer: false)
        delegate = self
        setupWindow()
        setupView()
    }

    func show(_ startupBlock: @escaping () -> Void) {
        accessibilityView.updatePermissionStatus(SystemPermissions.updateAccessibilityIsGranted())
        center()
        App.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        SystemPermissions.pollPermissionsToUpdatePermissionsWindow(startupBlock)
    }

    private func setupWindow() {
        title = NSLocalizedString("AltTab needs some permissions", comment: "")
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        styleMask.insert([.miniaturizable, .closable])
    }

    private func setupView() {
        let appIcon = LightImageView()
        appIcon.updateWithResizedCopy(App.appIcon, NSSize(width: 80, height: 80))
        appIcon.fit(80, 80)
        let appText = TitleLabel(NSLocalizedString("AltTab needs some permissions", comment: ""))
        appText.preferredMaxLayoutWidth = 380
        appText.font = .systemFont(ofSize: 25, weight: .regular)
        let header = NSStackView(views: [appIcon, appText])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.spacing = GridView.interPadding
        accessibilityView = PermissionView(
            "accessibility",
            NSLocalizedString("Accessibility", comment: ""),
            NSLocalizedString("This permission is needed to focus windows after you release the shortcut", comment: ""),
            NSLocalizedString("Open Accessibility Preferences…", comment: ""),
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            SystemPermissions.updateAccessibilityIsGranted
        )
        let rows = [
            [header],
            [accessibilityView],
        ]
        let view = GridView(rows as! [[NSView]])
        view.fit()
        setContentSize(view.fittingSize)
        contentView = view
    }
}

extension PermissionsWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        Logger.debug(SystemPermissions.preStartupPermissionsPassed)
        if !SystemPermissions.preStartupPermissionsPassed {
            if SystemPermissions.updateAccessibilityIsGranted() == .notGranted {
                Logger.error("Before using this app, you need to give permission in System Preferences > Security & Privacy > Privacy > Accessibility.",
                    "Please authorize and re-launch.",
                    "See https://help.rescuetime.com/article/59-how-do-i-enable-accessibility-permissions-on-mac-osx")
                App.shared.terminate(self)
            }
        } else {
            SystemPermissions.timerPermissionsToUpdatePermissionsWindow?.invalidate()
        }
    }
}