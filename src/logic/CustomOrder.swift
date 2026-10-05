import Cocoa

/// a window as the Custom Order remembers it: its app, and its title override, or its title
struct CustomOrderEntry: Codable, Hashable {
    var app: String
    var title: String
}

/// the order the user dragged windows into in the switcher; see CONTEXT.md.
/// It replaces Alphabetical Order for the windows it knows; the others follow, alphabetically
class CustomOrder {
    /// windows that aren't open are remembered too, up to this count, so they come back at their place
    private static let maxCount = 400
    private static var cache: (exact: [CustomOrderEntry: Int], apps: [String: Int])?

    static var entries: [CustomOrderEntry] { Preferences.customOrder }

    /// the user can drag windows in lists ordered alphabetically
    static func isEnabled(_ shortcutIndex: Int) -> Bool {
        return Preferences.windowOrder[shortcutIndex] == .alphabetical
    }

    static func entry(_ window: Window) -> CustomOrderEntry {
        let app = window.application.bundleIdentifier ?? ""
        let raw = window.title ?? ""
        return CustomOrderEntry(app: app.isEmpty ? window.application.displayName : app, title: Window.titleOverride(app, raw) ?? raw)
    }

    /// the window's position in the Custom Order. A window it doesn't know (e.g. a browser whose title changed)
    /// takes the place of its app's first known window, after it
    static func rank(_ window: Window) -> (position: Int, isApproximate: Bool)? {
        let (exact, apps) = indexes()
        let entry = entry(window)
        if let position = exact[entry] { return (position, false) }
        if let position = apps[entry.app] { return (position, true) }
        return nil
    }

    static func compare(_ w0: Window, _ w1: Window) -> ComparisonResult {
        switch (rank(w0), rank(w1)) {
            case (nil, nil): return .orderedSame
            case (_, nil): return .orderedAscending
            case (nil, _): return .orderedDescending
            case let (r0?, r1?):
                if r0.position != r1.position { return r0.position < r1.position ? .orderedAscending : .orderedDescending }
                if r0.isApproximate != r1.isApproximate { return r1.isApproximate ? .orderedAscending : .orderedDescending }
                return .orderedSame
        }
    }

    /// `shown` is the list as the user now sees it, after a drop. Remembered windows which aren't shown
    /// (closed, in another Workspace, filtered out) stay right after the window they followed
    static func save(_ shown: [Window]) {
        set(merged(shown.map { entry($0) }, entries))
    }

    static func merged(_ shown: [CustomOrderEntry], _ old: [CustomOrderEntry]) -> [CustomOrderEntry] {
        var visible = [CustomOrderEntry]()
        var seen = Set<CustomOrderEntry>()
        for entry in shown where seen.insert(entry).inserted {
            visible.append(entry)
        }
        var followers = [CustomOrderEntry?: [CustomOrderEntry]]()
        var anchor: CustomOrderEntry? = nil
        for entry in old {
            if seen.contains(entry) {
                anchor = entry
            } else {
                followers[anchor, default: []].append(entry)
            }
        }
        var result = followers[nil] ?? []
        for entry in visible {
            result.append(entry)
            result += followers[entry] ?? []
        }
        if result.count > maxCount {
            // forget the remembered windows which aren't shown first, from the end
            var excess = result.count - maxCount
            result = result.reversed().filter { entry in
                if excess > 0 && !seen.contains(entry) { excess -= 1; return false }
                return true
            }.reversed()
        }
        return result
    }

    static func reset() {
        set([])
    }

    private static func set(_ entries: [CustomOrderEntry]) {
        Logger.info("custom order:", entries.count, "windows")
        Preferences.set("customOrder", entries)
        cache = nil
    }

    private static func indexes() -> (exact: [CustomOrderEntry: Int], apps: [String: Int]) {
        if let cache { return cache }
        var exact = [CustomOrderEntry: Int]()
        var apps = [String: Int]()
        for (i, entry) in entries.enumerated() {
            if exact[entry] == nil { exact[entry] = i }
            if apps[entry.app] == nil { apps[entry.app] = i }
        }
        cache = (exact, apps)
        return (exact, apps)
    }
}
