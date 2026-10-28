#!/bin/zsh
set -eu
cd "${0:A:h}"
stageDir=$(mktemp -d /private/tmp/voicetrace-build.XXXXXX)
cp Sources/*.swift "$stageDir/"
buildFlags=()
if [[ "${1:-clean}" == personal ]]; then
 appName='声迹 VoiceTrace.app'
 buildFlags=(-D PERSONAL_BUILD)
 packageName='VoiceTrace-Mac-0.9.0-Personal.zip'
else
 appName='声迹 VoiceTrace Clean.app'
 packageName='VoiceTrace-Mac-0.9.0-Clean.zip'
fi
stageBundle="$stageDir/$appName"
mkdir -p "$stageBundle/Contents/MacOS" "$stageBundle/Contents/Resources"
for archName in $(uname -m) $([[ $(uname -m) == arm64 ]] && print x86_64 || print arm64); do
 /usr/bin/swiftc "${buildFlags[@]}" -swift-version 5 -parse-as-library -O -target "$archName-apple-macosx13.0" -module-cache-path /private/tmp/voicetrace-module-cache "$stageDir"/*.swift -o "$stageDir/VoiceTrace-$archName" -framework SwiftUI -framework AppKit -framework AVFoundation -framework Security -framework PDFKit -framework LocalAuthentication
done
/usr/bin/lipo -create "$stageDir/VoiceTrace-x86_64" "$stageDir/VoiceTrace-arm64" -output "$stageBundle/Contents/MacOS/VoiceTrace"
cp Assets/VoiceTrace.icns Assets/VoiceTrace.png "$stageBundle/Contents/Resources/"
cp Assets/Info.plist "$stageBundle/Contents/Info.plist"
if [[ "${1:-clean}" == personal ]]; then
 /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.tim.tingjian' "$stageBundle/Contents/Info.plist"
fi
/usr/bin/xattr -cr "$stageBundle"
/usr/bin/codesign --force --sign - --entitlements Assets/entitlements.plist "$stageBundle"
/usr/bin/codesign --verify --deep --strict "$stageBundle"
/usr/bin/ditto --norsrc --noextattr "$stageBundle" "outputs/$appName"
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$stageBundle" "outputs/$packageName"
print "构建与签名检查通过：outputs/$appName"
