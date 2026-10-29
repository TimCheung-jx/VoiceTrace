#!/bin/zsh
set -eu
cd "${0:A:h}/.."
stage=$(mktemp -d /private/tmp/voicetrace-audio-checks.XXXXXX)
cp Sources/Audio.swift Sources/Protocol.swift Next/Tests/AudioChecks.swift "$stage/"
flags=()
if [[ "${VT_AUDIO_OPTIMIZED:-0}" == 1 ]]; then flags=(-O); fi
swiftc "${flags[@]}" -swift-version 5 -parse-as-library -module-cache-path /private/tmp/voicetrace-module-cache "$stage"/*.swift -framework AVFoundation -o "$stage/check"
"$stage/check"
