import Cocoa

/// a project context. The user assigns windows to it in Preferences › Windows; see CONTEXT.md
struct WorkspaceEntry: Codable {
    var id: String
    var name: String
}

/// a column of the switcher. Apps are assigned to a Group; windows of unassigned apps go to the Ungrouped column
struct GroupEntry: Codable {
    var name: String
    /// bundle identifier prefixes (like the blacklist) or app names
    var apps: [String]

    func contains(_ application: Application) -> Bool {
        let bundleId = application.bundleIdentifier ?? ""
        let appName = application.localizedName ?? ""
        return apps.contains { app in
            !app.isEmpty && (bundleId.hasPrefix(app) || appName.caseInsensitiveCompare(app) == .orderedSame)
        }
    }

    static func defaults() -> String {
        return Preferences.jsonEncode([
            GroupEntry(name: "Browser", apps: ["com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox", "company.thebrowser.Browser"]),
            GroupEntry(name: "IDE", apps: ["com.jetbrains.", "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.todesktop.230313mzl4w4u92"]),
            GroupEntry(name: "Utils", apps: ["com.cmuxterm.app", "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"]),
        ])
    }
}

/// the switcher columns: one per Group, in preference order, then Ungrouped
class WindowGroups {
    static var isEnabled: Bool { !Preferences.groups.isEmpty }

    static var columnNames: [String] {
        Preferences.groups.map { $0.name } + [NSLocalizedString("Ungrouped", comment: "")]
    }

    static func columnIndex(_ window: Window) -> Int {
        let groups = Preferences.groups
        return groups.firstIndex { $0.contains(window.application) } ?? groups.count
    }
}

/// which Workspaces each window belongs to, and which Workspace is active.
/// This state is saved to disk so that restarting AltTab, an app, or the Mac doesn't lose it:
/// - AltTab restarts: window ids are owned by the WindowServer and survive, so windows match exactly
/// - app restarts / reboots: windows get new ids; restored windows are matched by app + title (+ frame to break ties)
class Workspaces {
    private struct SavedWindow: Codable {
        var wid: CGWindowID
        var bundleId: String
        var title: String
        var frame: CGRect?
        var workspaceIds: [String]
        /// when the window disappeared; kept for a while to re-match it when its app relaunches
        var closedAt: Double?
    }

    private struct State: Codable {
        /// window ids are only unique within one boot session
        var bootTime: Double
        var activeWorkspaceId: String?
        var windows: [SavedWindow]
        /// each Workspace's windows, most recently focused first, by Workspace id
        var focusOrders: [String: [CGWindowID]]?
    }

    /// windows appearing this soon after AltTab launched existed before; they only join a Workspace if they match saved state
    private static let discoveryDuration = 15.0
    /// windows appearing this soon after their app launched are likely restored by the app; they're matched by title
    private static let appRestoreDuration = 20.0
    /// restored windows may get their final title a bit later (e.g. browsers); we keep trying to match them for that long
    private static let pendingMatchDuration = 30.0
    private static let orphanMaxAge = 7.0 * 24 * 3600
    private static let orphanMaxCount = 500

    private static var launchedAt = Date().timeIntervalSince1970
    private static var bootTime = Double(0)
    private static var activeId: String?
    /// saved state of live windows, by window id
    private static var live = [CGWindowID: SavedWindow]()
    /// saved state of windows not currently open; candidates to re-match restored windows
    private static var orphans = [SavedWindow]()
    /// restored windows we couldn't match yet, and when they appeared
    private static var pending = [CGWindowID: Double]()
    /// each Workspace's windows, most recently focused first, counting only focus while that Workspace was active.
    /// Switching to a Workspace restores this order, so the switcher is as the user left it
    private static var focusOrders = [String: [CGWindowID]]()
    private static let focusOrderMaxCount = 200
    /// while a switch raises windows, their focus events arrive in any order; they must not count as use
    private static var isSettling = false
    private static let settleDelay = DispatchTimeInterval.milliseconds(800)
    private static var settleWorkItem: DispatchWorkItem?
    private static var lastFocusEventWid: CGWindowID?
    private static var saveWorkItem: DispatchWorkItem?
    /// saving before loading would overwrite the saved state with an empty one
    private static var isInitialized = false

    static var fileUrl: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AltTab", isDirectory: true)
        return dir.appendingPathComponent("workspaces.json")
    }

    static func initialize() {
        launchedAt = Date().timeIntervalSince1970
        bootTime = currentBootTime()
        isInitialized = true
        guard let data = try? Data(contentsOf: fileUrl) else {
            Logger.info("no saved workspaces state at", fileUrl.path)
            return
        }
        guard let state = try? JSONDecoder().decode(State.self, from: data) else {
            Logger.error("couldn't decode saved workspaces state at", fileUrl.path)
            return
        }
        activeId = state.activeWorkspaceId
        let sameBoot = abs(state.bootTime - bootTime) < 60
        if sameBoot { focusOrders = state.focusOrders ?? [:] }
        orphans = state.windows.map { saved in
            var saved = saved
            saved.closedAt = saved.closedAt ?? launchedAt
            // after a reboot, ids mean nothing; only title matching can apply
            if !sameBoot { saved.wid = 0 }
            return saved
        }
        Logger.info("loaded workspaces state", "sameBoot:", sameBoot, "windows:", orphans.count, "active:", activeId ?? "nil")
    }

    // MARK: - queries

    static var active: WorkspaceEntry? {
        guard let activeId else { return nil }
        return Preferences.workspaces.first { $0.id == activeId }
    }

    static func workspaceIds(_ window: Window) -> [String] {
        guard let wid = window.cgWindowId else { return [] }
        return live[wid]?.workspaceIds ?? []
    }

    static func isInActiveWorkspace(_ window: Window) -> Bool {
        guard let active else { return true }
        return workspaceIds(window).contains(active.id)
    }

    /// in no existing Workspace: it existed before AltTab started, or its Workspaces were deleted
    static func isUnassigned(_ window: Window) -> Bool {
        let ids = workspaceIds(window)
        return !Preferences.workspaces.contains { ids.contains($0.id) }
    }

    static func isShown(_ window: Window, _ preference: WorkspacesToShowPreference) -> Bool {
        switch preference {
            case .all: return true
            case .active: return isInActiveWorkspace(window)
            // windowless apps belong to no Workspace, but launching an app is part of working in any Workspace
            case .activeAndUnassigned: return isInActiveWorkspace(window) || isUnassigned(window)
        }
    }

    // MARK: - window lifecycle

    static func windowAppeared(_ window: Window) {
        guard let wid = window.cgWindowId, let bundleId = window.application.bundleIdentifier,
              bundleId != App.bundleIdentifier, live[wid] == nil else { return }
        let now = Date().timeIntervalSince1970
        let title = window.title ?? ""
        if let i = orphans.firstIndex(where: { $0.wid != 0 && $0.wid == wid && $0.bundleId == bundleId }) {
            claim(i, window, "same window id")
            return
        }
        let isPreExisting = now - launchedAt < discoveryDuration
        let isRestored = (window.application.runningApplication.launchDate?.timeIntervalSince1970).map { now - $0 < appRestoreDuration } ?? false
        if isPreExisting || isRestored {
            if let i = bestTitleMatch(bundleId, title, window) {
                claim(i, window, "same app and title")
                return
            }
            if orphans.contains(where: { $0.bundleId == bundleId }) {
                pending[wid] = now
                live[wid] = saved(window, [])
                Logger.info("window unassigned (restored by its app, waiting for its title to match)", wid, bundleId, title)
                return
            }
            if isPreExisting {
                live[wid] = saved(window, [])
                Logger.info("window unassigned (existed before)", wid, bundleId, title)
                return
            }
            // an app launched fresh, with nothing to restore: its window is a new window
        }
        joinActiveWorkspace(window)
    }

    /// new windows join the active Workspace, so the switcher shows them right away
    private static func joinActiveWorkspace(_ window: Window) {
        let wid = window.cgWindowId!
        guard let active else {
            live[wid] = saved(window, [])
            Logger.info("new window unassigned (no active workspace)", wid, window.application.bundleIdentifier ?? "", window.title ?? "")
            return
        }
        live[wid] = saved(window, [active.id])
        // its focus event may come before it joined; a new window is the most recent one anyway
        moveToFront(wid, active.id)
        Logger.info("new window joined the active workspace", wid, window.application.bundleIdentifier ?? "", window.title ?? "", active.name)
        scheduleSave()
    }

    static func windowTitleChanged(_ window: Window) {
        guard let wid = window.cgWindowId, let bundleId = window.application.bundleIdentifier else { return }
        if let appearedAt = pending[wid] {
            if Date().timeIntervalSince1970 - appearedAt > pendingMatchDuration {
                pending.removeValue(forKey: wid)
            } else if let i = bestTitleMatch(bundleId, window.title ?? "", window) {
                pending.removeValue(forKey: wid)
                live.removeValue(forKey: wid)
                claim(i, window, "same app and title, after title change")
                App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
                return
            }
        }
        if !(live[wid]?.workspaceIds.isEmpty ?? true) {
            scheduleSave()
        }
    }

    static func windowRemoved(_ window: Window) {
        guard let wid = window.cgWindowId, var saved = live.removeValue(forKey: wid) else { return }
        pending.removeValue(forKey: wid)
        for id in focusOrders.keys {
            focusOrders[id]!.removeAll { $0 == wid }
        }
        if saved.workspaceIds.isEmpty { return }
        refresh(&saved, window)
        saved.closedAt = Date().timeIntervalSince1970
        orphans.append(saved)
        scheduleSave()
    }

    private static func claim(_ orphanIndex: Int, _ window: Window, _ reason: String) {
        let orphan = orphans.remove(at: orphanIndex)
        live[window.cgWindowId!] = saved(window, orphan.workspaceIds)
        let names = orphan.workspaceIds.compactMap { id in Preferences.workspaces.first { $0.id == id }?.name }
        Logger.info("window restored to workspaces", window.cgWindowId!, orphan.bundleId, window.title ?? "", names, "reason:", reason)
        scheduleSave()
    }

    private static func bestTitleMatch(_ bundleId: String, _ title: String, _ window: Window) -> Int? {
        guard !title.isEmpty else { return nil }
        var candidates = orphans.indices.filter { orphans[$0].bundleId == bundleId && orphans[$0].title == title }
        guard !candidates.isEmpty else { return nil }
        // a saved window which is still open will be matched by its id; its state isn't up for grabs
        let openWids = openWindowIds()
        candidates.removeAll { orphans[$0].wid != 0 && openWids.contains(orphans[$0].wid) }
        guard let frame = frame(window) else { return candidates.first }
        return candidates.min { distance(orphans[$0].frame, frame) < distance(orphans[$1].frame, frame) }
    }

    private static func openWindowIds() -> Set<CGWindowID> {
        guard let infos = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[CFString: Any]] else { return [] }
        return Set(infos.compactMap { ($0[kCGWindowNumber] as? NSNumber)?.uint32Value })
    }

    private static func distance(_ a: CGRect?, _ b: CGRect) -> CGFloat {
        guard let a else { return .greatestFiniteMagnitude }
        return abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    private static func frame(_ window: Window) -> CGRect? {
        guard let position = window.position, let size = window.size else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func saved(_ window: Window, _ workspaceIds: [String]) -> SavedWindow {
        return SavedWindow(wid: window.cgWindowId!, bundleId: window.application.bundleIdentifier ?? "",
            title: window.title ?? "", frame: frame(window), workspaceIds: workspaceIds, closedAt: nil)
    }

    private static func refresh(_ saved: inout SavedWindow, _ window: Window) {
        saved.title = window.title ?? saved.title
        saved.frame = frame(window) ?? saved.frame
    }

    // MARK: - user actions

    static func setMembership(_ window: Window, _ workspaceId: String, _ isMember: Bool) {
        if workspaceIds(window).contains(workspaceId) != isMember {
            toggleMembership(window, workspaceId)
        }
    }

    static func toggleMembership(_ window: Window, _ workspaceId: String) {
        guard let wid = window.cgWindowId else { return }
        var saved = live[wid] ?? saved(window, [])
        if let i = saved.workspaceIds.firstIndex(of: workspaceId) {
            saved.workspaceIds.remove(at: i)
        } else {
            saved.workspaceIds.append(workspaceId)
        }
        live[wid] = saved
        pending.removeValue(forKey: wid)
        Logger.info("window workspaces changed", wid, window.title ?? "", saved.workspaceIds)
        scheduleSave()
    }

    /// makes the Workspace active, then brings its windows forward and restores the order they were last used in
    static func activate(_ workspaceId: String?) {
        activeId = workspaceId
        Logger.info("active workspace", active?.name ?? "nil")
        Menubar.refreshTitle()
        scheduleSave()
        guard let workspaceId else { return }
        Windows.updateSpacesAndTabsState()
        let members = orderedMembers(workspaceId)
        let raisable = members.filter { !$0.isMinimized && !$0.isHidden }
        guard let target = raisable.first else {
            Logger.info("workspace has no window to focus", active?.name ?? "")
            return
        }
        let order = [target] + members.filter { $0 !== target }
        isSettling = true
        // only raise windows on the current Space(s): raising others would make macOS jump between Spaces.
        // The least recent is raised first, so the windows end up stacked in the order they were used
        let others = raisable.dropFirst()
            .filter { window in Spaces.visibleSpaces.contains { window.spaceIds.contains($0) } }
            .prefix(12)
            .reversed()
        for window in others {
            window.focus()
        }
        Logger.info("workspace focuses its last focused window", active?.name ?? "", target.cgWindowId ?? 0, target.application.displayName, target.title ?? "")
        target.focus()
        settleWorkItem?.cancel()
        let workItem = DispatchWorkItem { settle(workspaceId, order, target) }
        settleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: workItem)
    }

    /// the raises are done: put the Workspace's windows back in the order they were last used, whatever order
    /// their focus events came in, and make sure the target ended up focused
    private static func settle(_ workspaceId: String, _ order: [Window], _ target: Window) {
        isSettling = false
        guard activeId == workspaceId else { return }
        let front = order.filter { window in Windows.list.contains { $0 === window } }
        let rest = Windows.list
            .filter { window in !front.contains { $0 === window } }
            .sorted { $0.lastFocusOrder < $1.lastFocusOrder }
        for (i, window) in (front + rest).enumerated() {
            window.lastFocusOrder = i
        }
        focusOrders[workspaceId] = front.compactMap { $0.cgWindowId }
        if lastFocusEventWid != target.cgWindowId && Windows.list.contains(where: { $0 === target }) {
            Logger.info("workspace switch ended on another window; focusing the target again", target.cgWindowId ?? 0, lastFocusEventWid ?? 0)
            target.focus()
        }
        scheduleSave()
    }

    /// the Workspace's windows, most recently used in it first. Windows never focused in it come last
    private static func orderedMembers(_ workspaceId: String) -> [Window] {
        let order = focusOrders[workspaceId] ?? []
        let rank = { (window: Window) -> Int? in window.cgWindowId.flatMap { order.firstIndex(of: $0) } }
        return Windows.list
            .filter { !$0.isWindowlessApp && workspaceIds($0).contains(workspaceId) }
            .sorted { a, b in
                switch (rank(a), rank(b)) {
                    case let (ra?, rb?): return ra < rb
                    case (.some, nil): return true
                    case (nil, .some): return false
                    default: return a.lastFocusOrder < b.lastFocusOrder
                }
            }
    }

    /// records use of a window in the active Workspace
    static func windowFocused(_ window: Window) {
        lastFocusEventWid = window.cgWindowId
        guard !isSettling, let activeId, let wid = window.cgWindowId, workspaceIds(window).contains(activeId) else { return }
        moveToFront(wid, activeId)
    }

    private static func moveToFront(_ wid: CGWindowID, _ workspaceId: String) {
        var order = focusOrders[workspaceId] ?? []
        guard order.first != wid else { return }
        order.removeAll { $0 == wid }
        order.insert(wid, at: 0)
        focusOrders[workspaceId] = Array(order.prefix(focusOrderMaxCount))
        scheduleSave()
    }

    // MARK: - persistence

    static func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { save() }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: workItem)
    }

    static func save() {
        guard isInitialized else { return }
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let now = Date().timeIntervalSince1970
        for window in Windows.list {
            if let wid = window.cgWindowId, var saved = live[wid] {
                refresh(&saved, window)
                live[wid] = saved
            }
        }
        orphans.removeAll { now - ($0.closedAt ?? now) > orphanMaxAge }
        if orphans.count > orphanMaxCount {
            orphans.sort { ($0.closedAt ?? now) > ($1.closedAt ?? now) }
            orphans.removeLast(orphans.count - orphanMaxCount)
        }
        // unassigned windows carry nothing worth restoring
        let windows = live.values.filter { !$0.workspaceIds.isEmpty } + orphans
        let state = State(bootTime: bootTime, activeWorkspaceId: activeId, windows: windows, focusOrders: focusOrders)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try FileManager.default.createDirectory(at: fileUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileUrl, options: .atomic)
        } catch {
            Logger.error("couldn't save workspaces state", error)
        }
    }

    private static func currentBootTime() -> Double {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 else { return 0 }
        return Double(bootTime.tv_sec) + Double(bootTime.tv_usec) / 1_000_000
    }
}
