#!/bin/bash
# Build, sign and install BeszelBar into ~/Applications, then relaunch it. Runs on the Mac.
# Signs ad hoc with a fixed designated requirement (the bundle id), so the keychain sees every
# rebuild as the same app and one "Always Allow" lasts. Ad-hoc signing needs no keychain access,
# so this works over SSH too.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project BeszelBar.xcodeproj -scheme BeszelBar -configuration Release -derivedDataPath build/dd \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build > build/xcodebuild.log 2>&1 \
  || { grep -E "error:" build/xcodebuild.log | sort -u | head; exit 1; }
app=build/dd/Build/Products/Release/BeszelBar.app
codesign --force --deep --options runtime -s - \
  -r='designated => identifier "com.nohitdev.BeszelBar"' "$app"
codesign -dr - "$app" 2>&1 | grep -q 'identifier "com.nohitdev.BeszelBar"' \
  || { echo "signing rule not applied" >&2; exit 1; }
pkill -x BeszelBar || true
rm -rf ~/Applications/BeszelBar.app
cp -R "$app" ~/Applications/
open ~/Applications/BeszelBar.app
echo "installed $(codesign -dr - ~/Applications/BeszelBar.app 2>&1 | tail -1)"
