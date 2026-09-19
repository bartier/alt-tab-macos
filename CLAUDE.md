# AltTab (fork)

## Logs

The app always writes debug-level logs to `~/Library/Logs/AltTab/AltTab.log`, rotated at 25MB (older files: `AltTab.log.1` … `AltTab.log.3`). Implemented in `src/api-wrappers/Logger.swift` (`RotatingFileDestination`).

When the user reports something not working, or before implementing a feature that touches runtime behavior, read those logs to see what the app actually did. Console output stays gated behind the `--logs=<level>` launch flag; the file log is always on.

## Build

```sh
xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -derivedDataPath DerivedData CODE_SIGN_IDENTITY="-" MACOSX_DEPLOYMENT_TARGET=10.13 build
```

- `CODE_SIGN_IDENTITY="-"` — the Release xcconfig pins the upstream maintainer's Developer ID cert; ad-hoc signing matches how the installed app is signed.
- `MACOSX_DEPLOYMENT_TARGET=10.13` — the LetsMove pod targets 10.6 and fails on current SDKs (missing libarclite) without this.
- Product lands in `DerivedData/Build/Products/Release/AltTab.app`.
- Build only; the user copies the app to /Applications themselves.
