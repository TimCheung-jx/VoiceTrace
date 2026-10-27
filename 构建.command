#!/bin/zsh
set -eu
cd "${0:A:h}"
stageDir=$(mktemp -d /private/tmp/voicetrace-build.XXXXXX)
cp Sources/*.swift "$stageDir/"
appName='声迹 VoiceTrace Clean.app'
stageBundle="$stageDir/$appName"
mkdir -p "$stageBundle/Contents/MacOS" "$stageBundle/Contents/Resources"
for archName in $(uname -m) $([[ $(uname -m) == arm64 ]] && print x86_64 || print arm64); do
 /usr/bin/swiftc -swift-version 5 -parse-as-library -O -target "$archName-apple-macosx13.0" -module-cache-path /private/tmp/voicetrace-module-cache "$stageDir"/*.swift -o "$stageDir/VoiceTrace-$archName" -framework SwiftUI -framework AppKit -framework AVFoundation -framework Security -framework PDFKit -framework LocalAuthentication
done
/usr/bin/lipo -create "$stageDir/VoiceTrace-x86_64" "$stageDir/VoiceTrace-arm64" -output "$stageBundle/Contents/MacOS/VoiceTrace"
cp Assets/VoiceTrace.icns Assets/VoiceTrace.png "$stageBundle/Contents/Resources/"
cp Assets/Info.plist "$stageBundle/Contents/Info.plist"
/usr/bin/xattr -cr "$stageBundle"
/usr/bin/codesign --force --sign - --entitlements Assets/entitlements.plist "$stageBundle"
/usr/bin/codesign --verify --deep --strict "$stageBundle"
/usr/bin/ditto --norsrc --noextattr "$stageBundle" "outputs/$appName"
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$stageBundle" 'outputs/VoiceTrace-Mac-0.6.1-Clean.zip'
print "构建与签名检查通过：outputs/$appName"
