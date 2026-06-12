#!/usr/bin/env bash

set -ex

if [[ -z "${BUILD_DIR:-}" ]]; then
    # Local build: no Developer ID cert, so skip signing then ad-hoc sign with sealed
    # resources. macOS 26 TCC binds the Accessibility grant to a stable code identity,
    # which the linker-injected placeholder signature does not provide.
    set -o pipefail && xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -derivedDataPath DerivedData -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=10.13 build | scripts/xcbeautify
    APP=DerivedData/Build/Products/Release/AltTab.app
    codesign --force --deep --sign - --entitlements alt_tab_macos.entitlements "$APP"
    file "$APP/Contents/MacOS/AltTab"
else
    set -o pipefail && xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -derivedDataPath DerivedData | scripts/xcbeautify
    file "$BUILD_DIR/$XCODE_BUILD_PATH/$APP_NAME.app/Contents/MacOS/$APP_NAME"
fi
