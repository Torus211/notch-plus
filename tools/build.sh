#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO build
mkdir -p dist
app='dist/Notch Plus.app'
if [[ -d "$app" ]]; then
  mv "$app" "dist/Notch Plus.previous.$(date +%s).app"
fi
ditto '.build/DerivedData/Build/Products/Release/Notch Plus.app' "$app"
cp Configuration/InitialPreferences.plist "$app/Contents/Resources/InitialPreferences.plist"
cp LICENSE "$app/Contents/Resources/NotchPlus-LICENSE.txt"
cp THIRD_PARTY_LICENSES "$app/Contents/Resources/THIRD_PARTY_LICENSES.txt"
codesign --force --deep --sign - "$app"
codesign --force --sign - --entitlements BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements \
  "$app/Contents/XPCServices/BoringNotchXPCHelper.xpc"
codesign --force --sign - --entitlements boringNotch/boringNotch.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
echo "Ready: ${PWD}/$app"
