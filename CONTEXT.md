# AltTab (fork)

Window switcher for macOS, forked to separate windows from several employers so that one employer never sees another's windows, and to keep each project's windows together.

## Language

**Workspace**:
A project context the user works in: Me, or one of the employers' projects. A new window joins the Workspaces of the window it was opened from (its app's last focused window), else the Active Workspace. The user fixes or adds assignments in Preferences › Windows. Assignments survive restarts of AltTab, apps and the Mac; after a reboot a window is recognised by its app and its title override, or its title. An assignment whose window isn't open is kept and ignored. A window can belong to several Workspaces, or to none. The user switches the active Workspace from the menu bar icon, or with ⌘1…⌘9 while the switcher is open; switching brings its windows forward in the order they were last used.
_Avoid_: Company, context, profile, Space (that's macOS's)

**Active Workspace**:
The Workspace the user is working in now. There is at most one. With none active, the switcher shows every window, except in the Workspace search, which then shows none.

**Unassigned**:
A window that belongs to no Workspace: windows open before AltTab started that match no saved state, and new windows opened while no Workspace is active. Apps without windows count as Unassigned. A window stays Unassigned across AltTab restarts.
_Avoid_: Unknown

**Group**:
A column of the switcher: Browser, IDE, Utils… Apps are assigned to Groups (by bundle ID prefix or app name), so a window's Group comes from its app, whatever its Workspace. Windows of apps in no Group go to the **Ungrouped** column, always last.
_Avoid_: Category, section, lane

**Membership rule** (not built):
A title override that also picks a Workspace. The Workspace on an override is optional.
_Avoid_: Pattern, filter

**Sharing session** (not built):
The period during which the screen is being shown to one Workspace. Only that Workspace and Me may appear in the switcher.
_Avoid_: Screen share mode, presentation mode, privacy mode
_Open question_: a window can belong to several Workspaces, so sharing with one Workspace can show a window that also belongs to another.

## Shortcut lists

**Visible list**:
Shortcut 1 (Cmd+Tab). Windows visible on the current Space, standard switcher behaviour.

**Work core**:
Shortcut 2 (Option+Tab). Windows of the active Workspace, in Group columns.

**Everything list**:
Shortcut 3 (Option+backtick). Windows of every Workspace, and Unassigned ones, in Group columns.

**Workspace search**:
Shortcut 4 (Option+Space). Windows of the active Workspace only; none if no Workspace is active. The switcher stays open on release, and typing filters by app name, title and title override; Enter focuses the selection, which starts on the Workspace's previous window.

Lists showing one Workspace open even when it has no windows, naming it.
