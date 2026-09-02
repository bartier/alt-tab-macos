---
status: accepted
---
# Unknown windows are not hidden by a Sharing session

A Sharing session hides windows that belong to a Group other than the shared one, but a window with no Group (Unknown) is always shown. The safe-by-default alternative, hiding everything that is not explicitly allowed, was rejected because most personal apps are never assigned a Group and would vanish from every shortcut list the moment a session starts, making the feature too costly to keep on. The accepted gap is that a work window with no Membership rule can appear during a session; a menu-bar warning when Unknown windows are present during a session is the intended follow-up, not a change of this rule.
