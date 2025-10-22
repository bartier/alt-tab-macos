# AltTab

[![Screenshot](docs/public/demo/frontpage.jpg)](docs/public/demo/frontpage.jpg)

**AltTab** brings the power of Windows alt-tab to macOS

[Find out more on the official website](https://alt-tab-macos.netlify.app/)

## This Fork’s Differences

- Adds a fourth configurable shortcut: find “Shortcut 4” under `Preferences → Controls`.
- Windows list: show app name first, then window title for clearer identification. (0a30222, 2025-10-22)
- Fix: prevent AltTab from switching to the current window inadvertently. (1005e61, 2025-10-21)
- Feature: when showing applications, also allow showing windows for the selected application. (42ac480, 2025-10-21)
- Robustness: add fallback to handle multiple apps with the same bundle name. (061c359, 2025-09-10)
- Per-shortcut configuration: “Show in Switcher” now configurable per shortcut profile. (37603bb, 2025-06-06)
