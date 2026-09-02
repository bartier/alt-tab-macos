import XCTest
// the Xcode unit-tests target compiles WindowGroups.swift directly; the SwiftPM shim used for fast local runs wraps it in a module
#if canImport(WindowGroups)
@testable import WindowGroups
#endif

final class WindowGroupsTests: XCTestCase {
    let me = WindowGroup(id: "me", name: "Me", color: "#888888", alwaysVisibleWhileSharing: true)
    let g = WindowGroup(id: "g", name: "GGG", color: "#00aa00")
    let w = WindowGroup(id: "w", name: "WWW", color: "#aa0000")
    var groups: [WindowGroup] { [me, g, w] }

    func rule(_ bundle: String = "", _ match: TitleMatch = .contains, _ pattern: String, _ replacement: String = "", group: String? = nil) -> MembershipRule {
        MembershipRule(bundleIdentifier: bundle, match: match, pattern: pattern, replacement: replacement, groupId: group)
    }

    func testFirstMatchingRuleInTableOrderDecidesLabelAndGroup() {
        let rules = [
            rule("com.google.Chrome", .regex, "- 1 - G$", "_GGG", group: "g"),
            rule("com.google.Chrome", .regex, "- G$", "late", group: "w"),
        ]
        let r = WindowGroups.resolve(bundleIdentifier: "com.google.Chrome", title: "JIRA - Google Chrome - 1 - G", rules: rules, groups: groups)
        XCTAssertEqual(r.replacement, "_GGG")
        XCTAssertEqual(r.group, g)
    }

    func testEmptyPatternWithGroupAssignsEveryWindowOfTheAppWithoutRelabelling() {
        let rules = [rule("org.whispersystems.signal-desktop", .contains, "", group: "me")]
        let r = WindowGroups.resolve(bundleIdentifier: "org.whispersystems.signal-desktop", title: "Signal (2)", rules: rules, groups: groups)
        XCTAssertNil(r.replacement)
        XCTAssertEqual(r.group, me)
    }

    func testEmptyPatternWithoutGroupIsANoOp() {
        let rules = [rule("com.spotify.client", .contains, "", "should not apply"), rule("com.spotify.client", .contains, "Spotify", "Music", group: "me")]
        let r = WindowGroups.resolve(bundleIdentifier: "com.spotify.client", title: "Spotify Premium", rules: rules, groups: groups)
        XCTAssertEqual(r.replacement, "Music")
        XCTAssertEqual(r.group, me)
    }

    func testDanglingGroupIdResolvesToUnknownButKeepsTheLabel() {
        let rules = [rule("com.google.Chrome", .regex, "- 4 - M$", "MMM", group: "deleted")]
        let r = WindowGroups.resolve(bundleIdentifier: "com.google.Chrome", title: "Slack - Google Chrome - 4 - M", rules: rules, groups: groups)
        XCTAssertEqual(r.replacement, "MMM")
        XCTAssertNil(r.group)
    }

    func testNoSessionAllowsEveryGroup() {
        XCTAssertTrue(WindowGroups.isAllowed(w, sharingWith: nil))
        XCTAssertTrue(WindowGroups.isAllowed(nil, sharingWith: nil))
    }

    func testSessionAllowsSharedGroupAlwaysVisibleGroupsAndUnknownOnly() {
        XCTAssertTrue(WindowGroups.isAllowed(g, sharingWith: "g"))
        XCTAssertTrue(WindowGroups.isAllowed(me, sharingWith: "g"))
        XCTAssertTrue(WindowGroups.isAllowed(nil, sharingWith: "g"))
        XCTAssertFalse(WindowGroups.isAllowed(w, sharingWith: "g"))
    }

    func testWindowsOfOneAppOrderByGroupRankThenTitleWithUnknownLast() {
        let windows: [(WindowGroup?, String)] = [(nil, "zeta"), (w, "WWW"), (g, "b"), (g, "a"), (me, "_Me"), (nil, "alpha")]
        let sorted = windows.sorted { WindowGroups.isOrderedBefore($0.0, $0.1, $1.0, $1.1, groups: groups) }
        XCTAssertEqual(sorted.map { $0.1 }, ["_Me", "a", "b", "WWW", "alpha", "zeta"])
    }

    func testGroupListDecodesWithMissingOptionalFields() throws {
        let json = "[{\"name\":\"GGG\",\"color\":\"#00aa00\"}]".data(using: .utf8)!
        let decoded = try JSONDecoder().decode([WindowGroup].self, from: json)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "GGG")
        XCTAssertFalse(decoded[0].alwaysVisibleWhileSharing)
        XCTAssertFalse(decoded[0].id.isEmpty)
    }
}
