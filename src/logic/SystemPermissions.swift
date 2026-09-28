import Cocoa

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static var accessibilityPermission = PermissionStatus.notGranted
    /// this fork doesn't use Screen Recording: no thumbnails, no previews; it never asks for the permission
    static let screenRecordingPermission = PermissionStatus.skipped
    static var preStartupPermissionsPassed = false
    static var timerPermissionsToUpdatePermissionsWindow: Timer?
    static var timerPermissionsRemovedWhileAltTabIsRunning: Timer?

    static func ensurePermissionsAreGranted(_ continueAppStartup: @escaping () -> Void) {
        let startupBlock = {
            pollPermissionsRemovedWhileAltTabIsRunning()
            continueAppStartup()
        }
        if updateAccessibilityIsGranted() != .notGranted {
            preStartupPermissionsPassed = true
            startupBlock()
        } else {
            App.app.permissionsWindow.show(startupBlock)
        }
    }

    static func pollPermissionsToUpdatePermissionsWindow(_ startupBlock: @escaping () -> Void) {
        timerPermissionsToUpdatePermissionsWindow = Timer(timeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async {
                checkPermissionsToUpdatePermissionsWindow(startupBlock)
            }
        }
        timerPermissionsToUpdatePermissionsWindow!.tolerance = 0.1
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timerPermissionsToUpdatePermissionsWindow!, .commonModes)
    }

    static func pollPermissionsRemovedWhileAltTabIsRunning() {
        timerPermissionsRemovedWhileAltTabIsRunning = Timer(timeInterval: 5, repeats: true) { _ in
            DispatchQueue.main.async {
                checkPermissionsWhileAltTabIsRunning()
            }
        }
        timerPermissionsRemovedWhileAltTabIsRunning!.tolerance = 1
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timerPermissionsRemovedWhileAltTabIsRunning!, .commonModes)
    }

    @discardableResult
    static func updateAccessibilityIsGranted() -> PermissionStatus {
        accessibilityPermission = detectAccessibilityIsGranted()
        return accessibilityPermission
    }

    private static func detectAccessibilityIsGranted() -> PermissionStatus {
        if #available(macOS 10.9, *) {
            return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary) ? .granted : .notGranted
        }
        return .granted
    }

    private static func checkPermissionsWhileAltTabIsRunning() {
        SystemPermissions.updateAccessibilityIsGranted()
        Logger.debug(accessibilityPermission)
        if accessibilityPermission == .notGranted {
            Logger.info("accessibilityPermission not granted; restarting")
            App.app.restart()
        }
    }

    private static func checkPermissionsToUpdatePermissionsWindow(_ startupBlock: @escaping () -> Void) {
        updateAccessibilityIsGranted()
        Logger.debug(accessibilityPermission, preStartupPermissionsPassed)
        if accessibilityPermission != App.app.permissionsWindow?.accessibilityView?.permissionStatus {
            App.app.permissionsWindow?.accessibilityView.updatePermissionStatus(accessibilityPermission)
        }
        if !preStartupPermissionsPassed {
            if accessibilityPermission != .notGranted {
                preStartupPermissionsPassed = true
                App.app.permissionsWindow?.close()
                startupBlock()
            }
        } else {
            if accessibilityPermission == .notGranted {
                App.app.restart()
            }
        }
    }
}
