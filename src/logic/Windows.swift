import Cocoa
import ApplicationServices.HIServices.AXAttributeConstants
import Carbon.HIToolbox.Events

class Windows {
    static var list = [Window]()
    static var focusedWindowIndex = Int(0)
    static var hoveredWindowIndex: Int?
    // When set, overrides the meaning of "active app" for filtering when
    // Preferences.appsToShow[shortcutIndex] == .active. Used to honor the
    // app selected in the Applications list when switching to the Windows list.
    static var activePidOverride: pid_t?
    private static var lastWindowActivityType = WindowActivityType.none
    // Tracks the most recently activated application (per AX activation events)
    // to guard against races when resolving the front app (e.g., launcher-triggered switches).
    static var lastActivatedPid: pid_t?
    static var lastActivatedAt: CFAbsoluteTime = 0

    static func setLastActivatedPid(_ pid: pid_t) {
        lastActivatedPid = pid
        lastActivatedAt = CFAbsoluteTimeGetCurrent()
    }

    static func resetInteractionState() {
        hoveredWindowIndex = nil
        lastWindowActivityType = .none
        WindowSearch.reset()
    }

    /// Updates windows "lastFocusOrder" to ensure unique values based on window z-order.
    /// Windows are ordered by their position in Spaces.windowsInSpaces() results,
    /// with topmost windows first.
    static func sortByLevel() {
        var windowLevelMap = [CGWindowID?: Int]()
        for (index, cgWindowId) in Spaces.windowsInSpaces(Spaces.visibleSpaces).enumerated() {
            windowLevelMap[cgWindowId] = index
        }
        list = list
            .sorted { w1, w2 in
                (windowLevelMap[w1.cgWindowId] ?? .max) < (windowLevelMap[w2.cgWindowId] ?? .max)
            }
            .enumerated()
            .map { (index, window) -> Window in
                window.lastFocusOrder = index
                return window
            }
    }

    /// reordered list based on preferences, keeping the original index
    private static func sort() {
        // pin the user's current selection to the window reference (not the slot)
        // so external events (e.g. title changes) that re-sort the list don't make
        // the highlight jump onto whatever happens to land at the old index
        let pinnedFocused = list.indices.contains(focusedWindowIndex) ? list[focusedWindowIndex] : nil
        let pinnedHovered = hoveredWindowIndex.flatMap { list.indices.contains($0) ? list[$0] : nil }
        // sort a local copy so the comparator can safely read `Windows.list`
        // (e.g. `displayTitle()` looks at siblings) without Swift trapping on
        // simultaneous exclusive + shared access to the static array.
        var sorted = list
        sorted.sort { isSortedBefore($0, $1, App.app.shortcutIndex) }
        list = sorted
        if let pinnedFocused, let i = list.firstIndex(where: { $0 === pinnedFocused }) {
            focusedWindowIndex = i
        }
        if let pinnedHovered, let i = list.firstIndex(where: { $0 === pinnedHovered }) {
            hoveredWindowIndex = i
        }
    }

    /// ordering comparator for a given shortcut index; reads no mutable UI state,
    /// so it can also order copies of the list for other indexes (e.g. CLI queries)
    static func isSortedBefore(_ w0: Window, _ w1: Window, _ shortcutIndex: Int) -> Bool {
        // separate buckets for these types of windows
        if w0.isWindowlessApp != w1.isWindowlessApp {
            return w1.isWindowlessApp
        }
        if Preferences.showHiddenWindows[shortcutIndex] == .showAtTheEnd && w0.isHidden != w1.isHidden {
            return w1.isHidden
        }
        if Preferences.showMinimizedWindows[shortcutIndex] == .showAtTheEnd && w0.isMinimized != w1.isMinimized {
            return w1.isMinimized
        }
        // sort within each buckets
        let sortType = Preferences.windowOrder[shortcutIndex]
        if sortType == .recentlyFocused {
            return w0.lastFocusOrder < w1.lastFocusOrder
        }
        if sortType == .recentlyCreated {
            return w1.creationOrder < w0.creationOrder
        }
        var order = ComparisonResult.orderedSame
        if sortType == .alphabetical {
            order = compareByAppNameThenWindowTitle(w0, w1)
        }
        if sortType == .space {
            if w0.isOnAllSpaces && w1.isOnAllSpaces {
                order = .orderedSame
            } else if w0.isOnAllSpaces {
                order = .orderedAscending
            } else if w1.isOnAllSpaces {
                order = .orderedDescending
            } else if let spaceIndex0 = w0.spaceIndexes.first, let spaceIndex1 = w1.spaceIndexes.first {
                order = spaceIndex0.compare(spaceIndex1)
            }
            if order == .orderedSame {
                order = compareByAppNameThenWindowTitle(w0, w1)
            }
        }
        if order == .orderedSame {
            order = w0.lastFocusOrder.compare(w1.lastFocusOrder)
        }
        return order == .orderedAscending
    }

    static func updateIsFullscreenOnCurrentSpace() {
        let windowsOnCurrentSpace = Windows.list.filter { !$0.isWindowlessApp }
        for window in windowsOnCurrentSpace {
            AXUIElement.retryAxCallUntilTimeout(after: .now() + .milliseconds(AXUIElement.retryDelayInMilliseconds)) { [weak window] in
                guard let window else { return }
                try updateWindowSizeAndPositionAndFullscreen(window.axUiElement!, window.cgWindowId!, window)
            }
        }
    }

    /// during a Sharing session, only windows of the shared Group, of always-visible Groups, or Unknown windows may show.
    /// Applies to every shortcut: the session is a safety net, not a per-list preference
    private static func isAllowedBySharingSession(_ window: Window) -> Bool {
        guard Preferences.isSharing else { return true }
        let group = window.group()
        let allowed = WindowGroups.isAllowed(group, sharingWith: Preferences.sharingWithGroup)
        if !allowed {
            Logger.debug("hidden by sharing session", window.cgWindowId ?? 0, window.application.bundleIdentifier ?? "", group?.name ?? "Unknown")
        }
        return allowed
    }

    /// app name, then Group rank (Unknown last), then title
    private static func compareByAppNameThenWindowTitle(_ w1: Window, _ w2: Window) -> ComparisonResult {
        let order = w1.application.displayName.localizedStandardCompare(w2.application.displayName)
        if order == .orderedSame {
            let t1 = w1.displayTitle()
            let t2 = w2.displayTitle()
            if WindowGroups.isOrderedBefore(w1.group(), t1, w2.group(), t2, groups: Preferences.windowGroups) { return .orderedAscending }
            if WindowGroups.isOrderedBefore(w2.group(), t2, w1.group(), t1, groups: Preferences.windowGroups) { return .orderedDescending }
            return .orderedSame
        }
        return order
    }

    static func setInitialFocusedAndHoveredWindowIndex() {
        let oldIndex = focusedWindowIndex
        focusedWindowIndex = 0
        ThumbnailsView.highlight(oldIndex)
        if let oldIndex = hoveredWindowIndex {
            hoveredWindowIndex = nil
            ThumbnailsView.highlight(oldIndex)
        }
        // When ordering by Recently Focused, always start selection on the
        // previously focused item (i.e. the next MRU), regardless of whether
        // the front app's focusedWindow has been observed yet. This avoids
        // a race where app.focusedWindow can be nil briefly after a switch,
        // causing selection to wrongly default to the current front app.
        if Preferences.windowOrder[App.app.shortcutIndex] != .recentlyFocused,
           let lastFocusedWindowIndex = getLastFocusedWindowIndex() {
            updateFocusedAndHoveredWindowIndex(lastFocusedWindowIndex)
        } else {
            cycleFocusedWindowIndex(1)
            if focusedWindowIndex == 0 {
                updateFocusedAndHoveredWindowIndex(0)
            }
        }
    }

    static func getLastFocusedWindowIndex() -> Int? {
        var index: Int? = nil
        var lastFocusOrderMin = Int.max
        Windows.list.enumerated().forEach {
            if !$0.element.isWindowlessApp && $0.element.lastFocusOrder < lastFocusOrderMin {
                lastFocusOrderMin = $0.element.lastFocusOrder
                index = $0.offset
            }
        }
        return index
    }

    static func appendAndUpdateFocus(_ window: Window) {
        list.forEach {
            $0.lastFocusOrder += 1
        }
        list.append(window)
        if list.count > ThumbnailsView.recycledViews.count {
            ThumbnailsView.recycledViews.append(ThumbnailView())
        }
    }

    static func removeAndUpdateFocus(_ window: Window) {
        let removedWindowOldFocusOrder = window.lastFocusOrder
        list.removeAll {
            if $0.lastFocusOrder == removedWindowOldFocusOrder {
                return true
            }
            if $0.lastFocusOrder > removedWindowOldFocusOrder {
                $0.lastFocusOrder -= 1
            }
            return false
        }
    }

    static func updateLastFocus(_ otherWindowAxUiElement: AXUIElement, _ otherWindowWid: CGWindowID) -> [Window]? {
        if let focusedWindow = (list.first { $0.isEqualRobust(otherWindowAxUiElement, otherWindowWid) }) {
            let focusedWindowOldFocusOrder = focusedWindow.lastFocusOrder
            var windowsToRefresh = [focusedWindow]
            list.forEach {
                if $0.lastFocusOrder == focusedWindowOldFocusOrder {
                    $0.lastFocusOrder = 0
                } else if $0.lastFocusOrder < focusedWindowOldFocusOrder {
                    $0.lastFocusOrder += 1
                }
                if $0.lastFocusOrder == 0 {
                    windowsToRefresh.append($0)
                }
            }
            return windowsToRefresh
        }
        return nil
    }

    static func updateFocusedAndHoveredWindowIndex(_ newIndex: Int, _ fromMouse: Bool = false) {
        var index: Int?
        if fromMouse && (newIndex != hoveredWindowIndex || lastWindowActivityType == .focus) {
            let oldIndex = hoveredWindowIndex
            hoveredWindowIndex = newIndex
            if let oldIndex {
                ThumbnailsView.highlight(oldIndex)
            }
            index = hoveredWindowIndex
            lastWindowActivityType = .hover
        }
        if (!fromMouse || Preferences.mouseHoverEnabled)
               && (newIndex != focusedWindowIndex || lastWindowActivityType == .hover) {
            let oldIndex = focusedWindowIndex
            focusedWindowIndex = newIndex
            ThumbnailsView.highlight(oldIndex)
            previewFocusedWindowIfNeeded()
            index = focusedWindowIndex
            lastWindowActivityType = .focus
        }
        guard let index else { return }
        ThumbnailsView.highlight(index)
        let focusedView = ThumbnailsView.recycledViews[index]
        App.app.thumbnailsPanel.thumbnailsView.scrollView.contentView.scrollToVisible(focusedView.frame)
        ThumbnailsMirror.setNeedsRefresh()
        voiceOverWindow(index)
    }

    static func previewFocusedWindowIfNeeded() {
        if App.app.appIsBeingUsed && SystemPermissions.screenRecordingPermission == .granted
               && Preferences.previewFocusedWindow && !Preferences.onlyShowApplications(App.app.shortcutIndex)
               && App.app.thumbnailsPanel.isKeyWindow,
           let window = focusedWindow(),
           let id = window.cgWindowId,
           let thumbnail = window.thumbnail,
           let position = window.position,
           let size = window.size {
            App.app.previewPanel.show(id, thumbnail, position, size)
        } else {
            App.app.previewPanel.orderOut(nil)
        }
    }

    static func voiceOverWindow(_ windowIndex: Int = focusedWindowIndex) {
        guard App.app.appIsBeingUsed && App.app.thumbnailsPanel.isKeyWindow else { return }
        // it seems that sometimes makeFirstResponder is called before the view is visible
        // and it creates a delay in showing the main window; calling it with some delay seems to work around this
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            let window = ThumbnailsView.recycledViews[windowIndex]
            if window.window_ != nil && window.window != nil {
                App.app.thumbnailsPanel.makeFirstResponder(window)
            }
        }
    }

    static func focusedWindow() -> Window? {
        return list.count > focusedWindowIndex ? list[focusedWindowIndex] : nil
    }

    static func cycleFocusedWindowIndex(_ step: Int, allowWrap: Bool = true) {
        let nextIndex = windowIndexAfterCycling(step)
        // don't wrap-around at the end, if key-repeat
        if (((step > 0 && nextIndex < focusedWindowIndex) || (step < 0 && nextIndex > focusedWindowIndex)) &&
            (!allowWrap || ATShortcut.lastEventIsARepeat || KeyRepeatTimer.timer?.isValid ?? false))
               // don't cycle to another row, if !allowWrap
               || (!allowWrap && list[nextIndex].rowIndex != list[focusedWindowIndex].rowIndex) {
            return
        }
        updateFocusedAndHoveredWindowIndex(nextIndex)
    }

    static func windowIndexAfterCycling(_ step: Int) -> Int {
        if list.count == 0 { return 0 }
        var iterations = 0
        var targetIndex = focusedWindowIndex
        repeat {
            let next = (targetIndex + step) % list.count
            targetIndex = next < 0 ? list.count + next : next
            iterations += 1
        } while !list[targetIndex].shouldShowTheUser && iterations <= list.count
        return targetIndex
    }

    static func moveFocusedWindowIndexAfterWindowDestroyedInBackground(_ index: Int) {
        if index < focusedWindowIndex {
            cycleFocusedWindowIndex(-1)
        }
    }

    static func updateFocusedWindowIndex() {
        if let focusedWindow = focusedWindow() {
            if !focusedWindow.shouldShowTheUser {
                cycleFocusedWindowIndex(windowIndexAfterCycling(1) > focusedWindowIndex ? 1 : -1)
            } else {
                previewFocusedWindowIfNeeded()
            }
        } else {
            cycleFocusedWindowIndex(-1)
        }
    }

    /// tabs detection is a flaky work-around the lack of public API to observe OS tabs
    /// see: https://github.com/lwouis/alt-tab-macos/issues/1540
    private static func detectTabbedWindows(_ window: Window, _ cgsWindowIds: [CGWindowID], _ visibleCgsWindowIds: [CGWindowID]) {
        if let cgWindowId = window.cgWindowId {
            if window.isMinimized || window.isHidden {
                if #available(macOS 13.0, *) {
                    // not exact after window merging
                    window.isTabbed = !cgsWindowIds.contains(cgWindowId)
                } else {
                    // not known
                    window.isTabbed = false
                }
            } else {
                window.isTabbed = !visibleCgsWindowIds.contains(cgWindowId)
            }
        }
    }

    static func updatesBeforeShowing(_ stabilizeActive: Bool = false) -> Bool {
        if list.count == 0 || MissionControl.state() == .showAllWindows || MissionControl.state() == .showFrontWindows { return false }
        // TODO: find a way to update space info when spaces are changed, instead of on every trigger
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refresh()
        let spaceIdsAndIndexes = Spaces.idsAndIndexes.map { $0.0 }
        lazy var cgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes)
        lazy var visibleCgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes, false)
        // Resolve the active PID once to avoid stale values when switching apps via tools like Alfred.
        // This snapshot is only used if filtering by active app is enabled.
        let activePidSnapshot: pid_t? = Windows.activePidOverride ?? Windows.resolveActivePid(stabilizeActive)
        // If filtering to the active app, ensure its focused window (per AX) is treated
        // as most recent to keep MRU order stable for toggling between last two windows.
        if Preferences.appsToShow[App.app.shortcutIndex] == .active,
           let pid = activePidSnapshot,
           let app = Applications.find(pid),
           let axApp = app.axUiElement {
            if let focusedAx = try? axApp.focusedWindow() {
                let wid = (try? focusedAx.cgWindowId()) ?? 0
                _ = Windows.updateLastFocus(focusedAx, wid)
            }
        }
        for window in list {
            detectTabbedWindows(window, cgsWindowIds, visibleCgsWindowIds)
            updatesWindowSpace(window)
            refreshIfWindowShouldBeShownToTheUser(window, activePidSnapshot)
        }
        refreshWhichWindowsToShowTheUser()
        for window in list {
            window.shouldShowTheUserIgnoringSearch = window.shouldShowTheUser
        }
        applySearchFilter()
        sort()
        if (!list.contains { $0.shouldShowTheUser }) {
            // while searching, an empty result is a normal state: we keep the switcher open
            // showing the search field, so the user can fix their query
            return WindowSearch.isActive
        }
        return true
    }

    /// re-derives shouldShowTheUser from the preference-based visibility and the current
    /// search query. Cheap enough to run on every keystroke, unlike updatesBeforeShowing()
    static func applySearchFilter() {
        for window in list {
            window.shouldShowTheUser = window.shouldShowTheUserIgnoringSearch
        }
        guard WindowSearch.isActive else {
            WindowSearch.hasNoMatches = false
            return
        }
        var someWindowMatches = false
        for window in list where window.shouldShowTheUser {
            if WindowSearch.matches(window) {
                someWindowMatches = true
            } else {
                window.shouldShowTheUser = false
            }
        }
        WindowSearch.hasNoMatches = !someWindowMatches
    }

    /// keeps the selection on a window the user can actually see; when the current selection
    /// is filtered out, we jump to the first match, as users expect from a search field
    static func focusFirstSearchMatchIfNeeded() {
        if list.indices.contains(focusedWindowIndex) && list[focusedWindowIndex].shouldShowTheUser { return }
        if let index = list.firstIndex(where: { $0.shouldShowTheUser }) {
            updateFocusedAndHoveredWindowIndex(index)
        }
    }

    /// lightweight refresh of Space and tab state for all windows; same per-trigger work
    /// updatesBeforeShowing() does, without touching shouldShowTheUser/sort/UI state.
    /// Used by CLI queries since Space data can be stale when the switcher hasn't been shown
    static func updateSpacesAndTabsState() {
        Spaces.refresh()
        let spaceIdsAndIndexes = Spaces.idsAndIndexes.map { $0.0 }
        lazy var cgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes)
        lazy var visibleCgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes, false)
        for window in list {
            detectTabbedWindows(window, cgsWindowIds, visibleCgsWindowIds)
            updatesWindowSpace(window)
        }
    }

    static func updatesWindowSpace(_ window: Window) {
        // macOS bug: if you tab a window, then move the tab group to another space, other tabs from the tab group will stay on the current space
        // you can use the Dock to focus one of the other tabs and it will teleport that tab in the current space, proving that it's a macOS bug
        // note: for some reason, it behaves differently if you minimize the tab group after moving it to another space
        if let cgWindowId = window.cgWindowId {
            let spaceIds = cgWindowId.spaces()
            window.spaceIds = spaceIds
            window.spaceIndexes = spaceIds.compactMap { spaceId in Spaces.idsAndIndexes.first { $0.0 == spaceId }?.1 }
            window.isOnAllSpaces = spaceIds.count > 1
        }
    }

    // dispatch screenshot requests off the main-thread, then wait for completion
    static func refreshThumbnails(_ windows: [Window], _ source: RefreshCausedBy) {
        var eligibleWindows = [Window]()
        for window in windows {
            if !window.isWindowlessApp, let cgWindowId = window.cgWindowId, cgWindowId != CGWindowID(bitPattern: -1) {
                eligibleWindows.append(window)
            }
        }
        if eligibleWindows.isEmpty { return }
        screenshotEligibleWindowsAndRefreshUi(eligibleWindows, source)
    }

    private static func screenshotEligibleWindowsAndRefreshUi(_ eligibleWindows: [Window], _ source: RefreshCausedBy) {
        for window in eligibleWindows {
            BackgroundWork.screenshotsQueue.async { [weak window] in
                if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                if let wid = window?.cgWindowId, let cgImage = wid.screenshot() {
                    if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                    DispatchQueue.main.async { [weak window] in
                        if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                        window?.refreshThumbnail(cgImage)
                    }
                }
            }
        }
    }

    static func refreshWhichWindowsToShowTheUser() {
        if Preferences.onlyShowApplications(App.app.shortcutIndex) {
            // Group windows by application and select the optimal main window
            let windowsGroupedByApp = Dictionary(grouping: list) { $0.application.pid }
            windowsGroupedByApp.forEach { (app, windows) in
                if windows.count > 1, let mainWindow = selectMainWindow(windows) {
                    windows.forEach { window in
                        if window.cgWindowId != mainWindow.cgWindowId {
                            window.shouldShowTheUser = false
                        }
                    }
                }
            }
        }
    }

    private static func refreshIfWindowShouldBeShownToTheUser(_ window: Window, _ activePidSnapshot: pid_t?) {
        window.shouldShowTheUser = isWindowShownToTheUser(window, activePidSnapshot, App.app.shortcutIndex)
    }

    /// pure predicate: doesn't mutate any window/UI state, so it can be evaluated
    /// for an arbitrary shortcut index (e.g. CLI queries) without affecting the open switcher
    static func isWindowShownToTheUser(_ window: Window, _ activePidSnapshot: pid_t?, _ shortcutIndex: Int) -> Bool {
        return
            isAllowedBySharingSession(window) &&
            !(window.application.bundleIdentifier.flatMap { id in
                Preferences.blacklist.contains {
                    id.hasPrefix($0.bundleIdentifier) &&
                        ($0.hide == .always || (window.isWindowlessApp && $0.hide != .none)) &&
                        $0.hideIn.contains(shortcutIndex)
                }
            } ?? false) &&
            {
                if Preferences.appsToShow[shortcutIndex] == .active {
                    return window.application.pid == activePidSnapshot
                }
                return true
            }() &&
            !(!(Preferences.showHiddenWindows[shortcutIndex] != .hide) && window.isHidden) &&
            ((!Preferences.hideWindowlessApps && window.isWindowlessApp) ||
                !window.isWindowlessApp &&
                !(!(Preferences.showFullscreenWindows[shortcutIndex] != .hide) && window.isFullscreen) &&
                !(!(Preferences.showMinimizedWindows[shortcutIndex] != .hide) && window.isMinimized) &&
                !(Preferences.spacesToShow[shortcutIndex] == .visible && !Spaces.visibleSpaces.contains { visibleSpace in window.spaceIds.contains { $0 == visibleSpace } }) &&
                !(Preferences.screensToShow[shortcutIndex] == .showingAltTab && !window.isOnScreen(NSScreen.preferred)) &&
                (Preferences.showTabsAsWindows || !window.isTabbed))
    }

    /// Determine the active app PID using multiple signals to avoid transient mismatches
    /// when switching via launchers (e.g., Alfred).
    /// Uses voting among: AX focused application, NSWorkspace frontmost application,
    /// CGWindow frontmost owner, WindowServer front process.
    static func resolveActivePid(_ stabilize: Bool = false) -> pid_t? {
        // First, honor a very recent activation notification if present.
        // This helps when global hotkeys fire before the system fully updates
        // frontmost signals across different APIs.
        if let recent = lastActivatedPid,
           CFAbsoluteTimeGetCurrent() - lastActivatedAt < 1.0,
           !isIgnoredTransientApp(recent) {
            return recent
        }

        // If requested, wait briefly when a transient overlay is frontmost
        if stabilize && Preferences.appsToShow[App.app.shortcutIndex] == .active {
            if let slps0 = slpsFrontProcessPid(), isIgnoredTransientApp(slps0) {
                for _ in 0..<12 { // ~300ms total
                    spinWait(milliseconds: 25)
                    if let pid = slpsFrontProcessPid(), !isIgnoredTransientApp(pid) {
                        return pid
                    }
                }
            }
        }

        let ax = axFocusedAppPid()
        let ws = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let cg = cgFrontmostRegularAppPid()
        let slps = slpsFrontProcessPid()

        var candidates = [pid_t]()
        if let p = ax { candidates.append(p) }
        if let p = ws { candidates.append(p) }
        if let p = cg { candidates.append(p) }
        if let p = slps { candidates.append(p) }

        if candidates.isEmpty { return nil }
        var counts = [pid_t: Int]()
        for p in candidates { counts[p, default: 0] += 1 }
        let maxCount = counts.values.max() ?? 1
        var topPids = counts.filter { $0.value == maxCount }.map { $0.key }

        // Filter out known transient overlays if they tie with others
        if topPids.count > 1 {
            let filtered = topPids.filter { !isIgnoredTransientApp($0) }
            if !filtered.isEmpty { topPids = filtered }
        }

        // When in doubt, prefer AX/Workspace which reflect keyboard focus
        if let p = ax, topPids.contains(p) { return p }
        if let p = ws, topPids.contains(p) { return p }
        if let p = cg, topPids.contains(p) { return p }
        if let p = slps, topPids.contains(p) { return p }
        return topPids.first ?? candidates.first
    }

    private static func slpsFrontProcessPid() -> pid_t? {
        var psn = ProcessSerialNumber()
        if _SLPSGetFrontProcess(&psn) == noErr {
            var pid: pid_t = 0
            GetProcessPID(&psn, &pid)
            if pid != 0 { return pid }
        }
        return nil
    }

    private static func axFocusedAppPid() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        if let focusedApp = ((try? systemWide.attribute(kAXFocusedApplicationAttribute, AXUIElement.self)) ?? nil),
           let pid = ((try? focusedApp.pid()) ?? nil) {
            return pid
        }
        return nil
    }

    private static func cgFrontmostRegularAppPid() -> pid_t? {
        for w in CGWindow.windows(.optionOnScreenOnly) { // front to back
            if w.layer() == 0, let pid = w.ownerPID(), pid != ProcessInfo.processInfo.processIdentifier {
                if let running = NSRunningApplication(processIdentifier: pid), running.activationPolicy == .regular {
                    return pid
                }
            }
        }
        return nil
    }

    private static func isIgnoredTransientApp(_ pid: pid_t) -> Bool {
        guard let running = NSRunningApplication(processIdentifier: pid), let id = running.bundleIdentifier else { return false }
        return id == "com.runningwithcrayons.Alfred" || id == "com.apple.Spotlight" || id == "com.raycast.macos"
    }

    private static func spinWait(milliseconds: Int) {
        RunLoop.current.run(mode: .common, before: Date(timeIntervalSinceNow: Double(milliseconds) / 1000.0))
    }

    /// Selects the most appropriate main window from a given list of windows.
    ///
    /// The selection criteria are as follows:
    /// 1. Prefer the focused window if it exists.
    /// 2. Prefer the main window of the application if the focused window is not found.
    ///
    /// - Parameter windows: An array of `Window` objects to select from.
    /// - Returns: The most appropriate `Window` object based on the selection criteria, or `nil` if the array is empty.
    static func selectMainWindow(_ windows: [Window]) -> Window? {
        let sortedWindows = windows.sorted { (window1, window2) -> Bool in
            // Prefer the focus window
            if window1.application.focusedWindow?.cgWindowId == window1.cgWindowId {
                return true
            } else if window2.application.focusedWindow?.cgWindowId == window2.cgWindowId {
                return false
            }
            // Prefer the main window
            if window1.isAppMainWindow() && !window2.isAppMainWindow() {
                return true
            } else if !window1.isAppMainWindow() && window2.isAppMainWindow() {
                return false
            }
            return true
        }
        return sortedWindows.first { $0.shouldShowTheUser }
    }
}

enum WindowActivityType: Int {
    case none = 0
    case hover = 1
    case focus = 2
}

/// type-to-search state. When a shortcut is set to "After release: Do nothing", the switcher
/// stays open without a held modifier, so plain keystrokes are free to build a query which
/// filters the list; Enter then focuses the selected window
class WindowSearch {
    static private(set) var query = ""
    /// query, folded and split; precomputed since it's matched against every window on every refresh
    static private var tokens = [String]()
    static var hasNoMatches = false

    static var isActive: Bool { !query.isEmpty }

    /// the shortcut currently showing the switcher must keep the UI up without a held modifier,
    /// and have type-to-search enabled
    static var isEnabledForCurrentShortcut: Bool {
        let index = App.app.shortcutIndex
        guard (0..<Preferences.typeToSearch.count).contains(index) else { return false }
        return Preferences.shortcutStyle[index] == .doNothingOnRelease && Preferences.typeToSearch[index]
    }

    static func reset() {
        setQuery("")
    }

    static func append(_ characters: String) {
        setQuery(query + characters)
    }

    static func deleteLastCharacter() {
        guard !query.isEmpty else { return }
        setQuery(String(query.dropLast()))
    }

    private static func setQuery(_ newQuery: String) {
        query = newQuery
        tokens = newQuery
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(separator: " ")
            .map { String($0) }
        if newQuery.isEmpty {
            hasNoMatches = false
        }
    }

    /// keys we claim while the switcher is open
    enum KeyAction {
        case select
        case deleteLastCharacter
        case clear
        case append(String)
    }

    /// decides whether a key press belongs to the search field rather than to the app underneath
    /// or to a "when active" shortcut. Called on the keyboard-events thread
    static func interpretKeyDown(_ cgEvent: CGEvent, _ keyCode: UInt32) -> KeyAction? {
        guard isEnabledForCurrentShortcut else { return nil }
        let flags = cgEvent.flags
        // modified key presses stay available for shortcuts (e.g. ⌘W in the app underneath)
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) { return nil }
        switch Int(keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter: return .select
            case kVK_Delete: return isActive ? .deleteLastCharacter : nil
            // first Escape clears the query, a second one closes the switcher (cancelShortcut)
            case kVK_Escape: return isActive ? .clear : nil
            // Tab keeps cycling the selection
            case kVK_Tab: return nil
            // Space stays the "focus selected window" shortcut until a search is started
            case kVK_Space: return isActive ? .append(" ") : nil
            default: break
        }
        guard let characters = typedCharacters(cgEvent) else { return nil }
        return .append(characters)
    }

    static func execute(_ action: KeyAction) {
        switch action {
            case .select: App.app.focusTargetFromKeyboard()
            case .deleteLastCharacter: App.app.deleteLastSearchCharacter()
            case .clear: App.app.clearSearchQuery()
            case .append(let characters): App.app.appendToSearchQuery(characters)
        }
    }

    /// the text this key press would insert, or nil for keys which type nothing
    /// (arrows and other function keys are mapped to Unicode's private-use area)
    private static func typedCharacters(_ cgEvent: CGEvent) -> String? {
        var length = 0
        var codeUnits = [UniChar](repeating: 0, count: 4)
        cgEvent.keyboardGetUnicodeString(maxStringLength: codeUnits.count, actualStringLength: &length, unicodeString: &codeUnits)
        guard length > 0 else { return nil }
        let characters = String(utf16CodeUnits: codeUnits, count: length)
        guard characters.unicodeScalars.allSatisfy({
            $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value)
        }) else { return nil }
        return characters
    }

    /// every token must appear somewhere in the app name or the window title; this makes
    /// "chr gh" find a GitHub tab in Chrome, without the surprises of fuzzy matching
    static func matches(_ window: Window) -> Bool {
        guard !tokens.isEmpty else { return true }
        let haystack = window.searchHaystack()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}
