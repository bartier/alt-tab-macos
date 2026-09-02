import Foundation

/// A Group is the owner of a window: the user, one of their companies, or Unknown (nil) when nothing assigns it.
/// Groups are ordered; the position in the list is the Group's rank.
struct WindowGroup: Codable, Equatable {
    var id: String
    var name: String
    /// hex color, e.g. "#ff8800"
    var color: String
    /// Groups the user marks as always visible while sharing (e.g. "Me")
    var alwaysVisibleWhileSharing: Bool

    init(id: String = UUID().uuidString, name: String, color: String, alwaysVisibleWhileSharing: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.alwaysVisibleWhileSharing = alwaysVisibleWhileSharing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#888888"
        alwaysVisibleWhileSharing = try c.decodeIfPresent(Bool.self, forKey: .alwaysVisibleWhileSharing) ?? false
    }
}

enum TitleMatch {
    case contains
    case exact
    case regex
}

/// A title override row: cosmetic replacement, plus an optional Group which makes it a Membership rule
struct MembershipRule {
    var bundleIdentifier: String
    var match: TitleMatch
    var pattern: String
    var replacement: String
    var groupId: String?
}

struct GroupResolution: Equatable {
    /// nil when no rule with a pattern matched
    var replacement: String?
    /// nil means Unknown
    var group: WindowGroup?
}

enum WindowGroups {
    /// pure: applies the first matching rule in table order. Reads no window or UI state.
    static func resolve(bundleIdentifier: String?, title: String?, rules: [MembershipRule], groups: [WindowGroup]) -> GroupResolution {
        let raw = title ?? ""
        let appId = bundleIdentifier ?? ""
        for rule in rules {
            // an empty pattern with a Group assigns every window of the app; without a Group it is a no-op row
            if rule.pattern.isEmpty && rule.groupId == nil { continue }
            if !rule.bundleIdentifier.isEmpty && !appId.hasPrefix(rule.bundleIdentifier) { continue }
            let hit: Bool
            switch rule.match {
                case _ where rule.pattern.isEmpty: hit = true
                case .contains: hit = raw.contains(rule.pattern)
                case .exact: hit = raw == rule.pattern
                case .regex: hit = raw.range(of: rule.pattern, options: .regularExpression) != nil
            }
            if hit {
                let group = rule.groupId.flatMap { id in groups.first { $0.id == id } }
                return GroupResolution(replacement: rule.pattern.isEmpty ? nil : rule.replacement, group: group)
            }
        }
        return GroupResolution(replacement: nil, group: nil)
    }

    /// pure: whether a window of `group` may be shown during the Sharing session with `sharingWith` (a Group id; nil/empty = not sharing).
    /// Unknown (nil group) is always allowed, by decision: untagged windows keep behaving like today.
    static func isAllowed(_ group: WindowGroup?, sharingWith: String?) -> Bool {
        guard let sharingWith, !sharingWith.isEmpty else { return true }
        guard let group else { return true }
        return group.id == sharingWith || group.alwaysVisibleWhileSharing
    }

    /// rank of a Group = its position in the list; Unknown ranks last
    static func rank(of group: WindowGroup?, in groups: [WindowGroup]) -> Int {
        guard let group, let i = groups.firstIndex(where: { $0.id == group.id }) else { return Int.max }
        return i
    }

    /// pure ordering for windows of the same app: Group rank, then title
    static func isOrderedBefore(_ group0: WindowGroup?, _ title0: String, _ group1: WindowGroup?, _ title1: String, groups: [WindowGroup]) -> Bool {
        let r0 = rank(of: group0, in: groups)
        let r1 = rank(of: group1, in: groups)
        if r0 != r1 { return r0 < r1 }
        return title0.localizedStandardCompare(title1) == .orderedAscending
    }
}
