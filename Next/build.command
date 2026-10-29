#!/bin/zsh
set -eu
cd "${0:A:h}/.."
stage=$(mktemp -d /private/tmp/voicetrace-next-build.XXXXXX)
flags=()
if [[ "${1:-clean}" == personal ]]; then
 flags=(-D PERSONAL_BUILD)
 appName='声迹VoiceTrace.app'
 bundleID='com.tim.voicetrace.next'
else
 appName='声迹VoiceTrace Clean.app'
 bundleID='org.voicetrace.next'
fi
sources=(Next/Sources/Core/*.swift Next/Sources/App/*.swift Sources/Protocol.swift Sources/Configurations.swift Sources/MemoryCredentials.swift Sources/Services.swift Sources/Audio.swift)
# 旧控制器及旧界面不参与构建；只适配已验证的音频、协议和钥匙串底层。
mkdir -p "$stage/Sources"
cp "${sources[@]}" "$stage/Sources/"
archs=($(uname -m))
if [[ "${VTNEXT_UNIVERSAL:-0}" == 1 ]]; then archs=(x86_64 arm64); fi
for arch in "${archs[@]}"; do
 swiftc "${flags[@]}" -swift-version 5 -parse-as-library -O -whole-module-optimization -target "$arch-apple-macosx13.0" -module-cache-path /private/tmp/voicetrace-module-cache "$stage/Sources"/*.swift -lsqlite3 -framework SwiftUI -framework AppKit -framework AVFoundation -framework Security -framework LocalAuthentication -o "$stage/VoiceTraceNext-$arch"
done
lipo -create "$stage"/VoiceTraceNext-* -output "$stage/VoiceTraceNext"
./Next/package.command "$stage" "${1:-clean}"
