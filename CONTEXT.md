# AltTab (fork)

Window switcher for macOS, forked to separate windows from several employers so that one employer never sees another's windows, and to keep each project's windows together.

## Language

**Workspace**:
A project context the user works in: Me, or one of the employers' projects. A new window joins the Active Workspace. The user fixes or adds assignments in Preferences › Windows. Assignments survive restarts. A window can belong to several Workspaces, or to none. The user switches the active Workspace from the menu bar icon; switching brings its windows forward in the order they were last used.
_Avoid_: Company, context, profile, Space (that's macOS's)

**Active Workspace**:
The Workspace the user is working in now. There is at most one. With none active, the switcher shows every window.

**Unassigned**:
A window that belongs to no Workspace: windows open before AltTab started that match no saved state, and new windows opened while no Workspace is active.
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
