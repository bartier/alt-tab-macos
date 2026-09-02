# AltTab (fork)

Window switcher for macOS, forked to separate windows from several employers so that one employer never sees another's windows.

## Language

**Group**:
The owner a window belongs to: Me, one of the companies, or Unknown when nothing assigns it. Every window has exactly one Group. A Group has a name, a colour and a rank; the rank orders windows of the same app.
_Avoid_: Company, context, workspace, profile

**Unknown**:
The Group of a window nothing assigns. Unknown windows are never hidden by a Sharing session.

**Membership rule**:
A title override that also picks a Group from the Group list. The Group on an override is optional.
_Avoid_: Pattern, filter

**Sharing session**:
The period during which the screen is being shown to one Group. Only that Group and Me may appear in the switcher.
_Avoid_: Screen share mode, presentation mode, privacy mode

## Shortcut lists

**Visible list**:
Shortcut 1 (Cmd+Tab). Windows visible on the current Space, standard switcher behaviour.

**Work core**:
Shortcut 2 (Option+Tab). Browser, terminal and editor windows of every Group, plus the task manager.

**Everything list**:
Shortcut 3 (Option+backtick). Work core plus every other app the user cares about.
