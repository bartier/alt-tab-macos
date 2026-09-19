import Cocoa

/// A non-interactive copy of the thumbnails panel, shown on the screens which don't hold the real panel.
/// It displays a bitmap snapshot of the real panel, so that the user sees the switcher on every screen,
/// while keyboard/mouse interaction keeps happening on a single, real panel.
class ThumbnailsMirrorPanel: NSPanel {
    let backgroundView = NSVisualEffectView()
    let snapshotView = NSView()

    convenience init() {
        self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = .canJoinAllSpaces
        level = .popUpMenu
        setAccessibilitySubrole(.unknown)
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        snapshotView.wantsLayer = true
        snapshotView.layer!.contentsGravity = .resize
        backgroundView.addSubview(snapshotView)
        contentView! = backgroundView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `size` is the real panel's size in points; it was laid out for `NSScreen.preferred`, so it can be
    /// larger than the screen this mirror is on. We scale it down to fit, rather than letting it overflow
    func update(_ snapshot: CGImage, _ captureScale: CGFloat, _ size: NSSize, _ screen: NSScreen) {
        hasShadow = Appearance.enablePanelShadow
        backgroundView.material = Appearance.material
        let fittedSize = ThumbnailsMirrorPanel.sizeFitting(size, screen.visibleFrame.size)
        let ratio = fittedSize.width / size.width
        backgroundView.maskImage = ThumbnailsView.roundedMaskImage((Appearance.windowCornerRadius * ratio).rounded())
        setContentSize(fittedSize)
        snapshotView.frame = NSRect(origin: .zero, size: fittedSize)
        // the snapshot is captured at the highest scale factor among screens; contentsScale maps its pixels back to points
        snapshotView.layer!.contentsScale = captureScale * size.width / fittedSize.width
        snapshotView.layer!.contents = snapshot
        alphaValue = 1
    }

    static func sizeFitting(_ size: NSSize, _ available: NSSize) -> NSSize {
        let ratio = min(1, min(available.width / size.width, available.height / size.height))
        guard ratio < 1 else { return size }
        return NSSize(width: (size.width * ratio).rounded(.down), height: (size.height * ratio).rounded(.down))
    }
}

/// Manages the lifecycle of the mirror panels; one per screen which doesn't hold the real panel
enum ThumbnailsMirror {
    private static var panels = [ThumbnailsMirrorPanel]()
    private static var refreshScheduled = false
    private static var mouseMovedMonitor: Any?

    /// re-render the mirrors on the next runloop pass; multiple calls within the same pass are coalesced
    static func setNeedsRefresh() {
        guard Preferences.showOnScreen == .all, NSScreen.screens.count > 1 else { return }
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async {
            refreshScheduled = false
            refresh()
        }
    }

    static func hide() {
        stopFollowingMouse()
        panels.forEach { $0.orderOut(nil) }
    }

    /// the real panel sits on the screen holding the mouse, and the mirrors cover the other screens. The user
    /// can move the mouse to another screen after the panel showed; the switcher they now look at must be the
    /// interactive one, otherwise their clicks land on a mirror, which dismisses the UI instead of selecting
    private static func startFollowingMouse() {
        guard mouseMovedMonitor == nil else { return }
        // the panel is non-activating, so AltTab is not the active app; a global monitor sees these events
        mouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { _ in
            moveRealPanelToScreenWithMouse()
        }
    }

    private static func stopFollowingMouse() {
        if let mouseMovedMonitor {
            NSEvent.removeMonitor(mouseMovedMonitor)
            ThumbnailsMirror.mouseMovedMonitor = nil
        }
    }

    private static func moveRealPanelToScreenWithMouse() {
        guard App.app.appIsBeingUsed, Preferences.showOnScreen == .all,
              let screen = NSScreen.withMouse(), screen != NSScreen.preferred else { return }
        NSScreen.preferred = screen
        let panel = App.app.thumbnailsPanel!
        // the panel was laid out for the previous screen; screens can differ in size, ratio and dpi
        Appearance.update()
        panel.thumbnailsView.updateItemsAndLayout()
        panel.setContentSize(panel.thumbnailsView.frame.size)
        panel.display()
        screen.repositionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        refresh()
    }

    private static func refresh() {
        guard App.app.appIsBeingUsed, Preferences.showOnScreen == .all else { hide(); return }
        let panel = App.app.thumbnailsPanel!
        let screens = NSScreen.screens.filter { $0 != NSScreen.preferred }
        guard !screens.isEmpty, panel.isVisible,
              let snapshot = snapshot(panel.thumbnailsView) else { hide(); return }
        let size = panel.thumbnailsView.frame.size
        let captureScale = maxScaleFactor()
        while panels.count < screens.count {
            panels.append(ThumbnailsMirrorPanel())
        }
        for (i, mirror) in panels.enumerated() {
            if i < screens.count {
                mirror.update(snapshot, captureScale, size, screens[i])
                screens[i].repositionPanel(mirror)
                mirror.orderFront(nil)
            } else {
                mirror.orderOut(nil)
            }
        }
        startFollowingMouse()
    }

    private static func maxScaleFactor() -> CGFloat {
        return NSScreen.screens.map { $0.backingScaleFactor }.max() ?? 2
    }

    /// we render the layer tree rather than using cacheDisplay, as most of the content
    /// (thumbnails, highlights, shadows) lives in layer properties, which cacheDisplay doesn't capture
    private static func snapshot(_ view: NSView) -> CGImage? {
        guard let layer = view.layer else { return nil }
        // capture at the highest scale factor among screens; the real panel may live on a low-dpi screen
        // while a mirror is on a retina one, and upscaling a 1x bitmap there looks blurry
        let scaleFactor = maxScaleFactor()
        let width = Int((view.bounds.width * scaleFactor).rounded())
        let height = Int((view.bounds.height * scaleFactor).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.scaleBy(x: scaleFactor, y: scaleFactor)
        context.setShouldSmoothFonts(false)
        context.setShouldSubpixelPositionFonts(true)
        context.setShouldSubpixelQuantizeFonts(false)
        withoutBackgroundLayers(view) { layer.render(in: context) }
        return context.makeImage()
    }

    /// `render(in:)` can't reproduce the live blur of a NSVisualEffectView: offscreen, it bakes a flat, fully
    /// opaque slab of the material's fallback tint instead. Left in the snapshot, that slab covers the mirror's
    /// own blur, so the mirror shows a flat panel while the real one shows a translucent one, tinted by whatever
    /// sits behind it. That is the tone mismatch between screens. We hide the background layers while capturing,
    /// so the snapshot holds only the content over transparent pixels, and the mirror blurs its own screen
    private static func withoutBackgroundLayers(_ view: NSView, _ render: () -> Void) {
        guard view is NSVisualEffectView, let sublayers = view.layer?.sublayers else { render(); return }
        // the material is drawn by the sublayers which back no subview; the others hold the content
        let subviewLayers = Set(view.subviews.compactMap { $0.layer }.map(ObjectIdentifier.init))
        let backgroundLayers = sublayers.filter { !subviewLayers.contains(ObjectIdentifier($0)) }
        // hiding and restoring within one transaction with actions off keeps the real panel from flickering
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayers.forEach { $0.isHidden = true }
        render()
        backgroundLayers.forEach { $0.isHidden = false }
        CATransaction.commit()
    }
}
