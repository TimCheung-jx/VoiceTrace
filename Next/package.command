#!/bin/zsh
set -eu
cd "${0:A:h}/.."
stage="$1"
mode="${2:-clean}"
if [[ "$mode" == personal ]]; then appName='声迹VoiceTrace.app';bundleID='com.tim.voicetrace.next';else appName='声迹VoiceTrace Clean.app';bundleID='org.voicetrace.next';fi
[[ -f "$stage/VoiceTraceNext" ]]
archs=($(lipo -archs "$stage/VoiceTraceNext"))
mkdir -p "$stage/$appName/Contents/MacOS" "$stage/$appName/Contents/Resources" outputs
cp "$stage/VoiceTraceNext" "$stage/$appName/Contents/MacOS/VoiceTrace"
swift -module-cache-path /private/tmp/voicetrace-module-cache Next/Tools/Icon.swift "$stage/icon.png"
mkdir -p "$stage/VoiceTrace.iconset"
for side in 16 32 128 256 512; do
 sips -z "$side" "$side" "$stage/icon.png" --out "$stage/VoiceTrace.iconset/icon_${side}x${side}.png" >/dev/null
 doubled=$((side*2))
 sips -z "$doubled" "$doubled" "$stage/icon.png" --out "$stage/VoiceTrace.iconset/icon_${side}x${side}@2x.png" >/dev/null
done
python3 Next/Tools/package_icon.py "$stage/VoiceTrace.iconset" "$stage/$appName/Contents/Resources/VoiceTracePurple.icns"
cp Next/Fixtures/response.json "$stage/$appName/Contents/Resources/"
/usr/bin/python3 - "$stage/$appName/Contents/Info.plist" "$bundleID" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
 plistlib.dump(dict(CFBundleExecutable='VoiceTrace',CFBundleIdentifier=sys.argv[2],CFBundleName='声迹VoiceTrace',CFBundleDisplayName='声迹VoiceTrace',CFBundleVersion='4',CFBundleShortVersionString='0.13.1',CFBundlePackageType='APPL',LSMinimumSystemVersion='13.0',CFBundleIconFile='VoiceTracePurple',NSMicrophoneUsageDescription='录音先保存在本机，语音通过您指定的服务识别。',NSDocumentsFolderUsageDescription='导入您选择的旧会议资料，原始文件保持不变。',NSHighResolutionCapable=True),f)
PY
xattr -cr "$stage/$appName"
codesign --force --sign - --entitlements Assets/entitlements.plist "$stage/$appName"
codesign --verify --deep --strict "$stage/$appName"
destination="outputs/VoiceTrace-0.13.1-${mode}/$appName"
mkdir -p "${destination:h}"
ditto --norsrc --noextattr "$stage/$appName" "$destination"
ditto -c -k --norsrc --noextattr --keepParent "$stage/$appName" "outputs/VoiceTrace-0.13.1-${mode}.zip"
print "构建通过：${destination}（架构：${archs[*]}；开发验证版）"
