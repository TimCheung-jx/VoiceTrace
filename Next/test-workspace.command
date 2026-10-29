#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d /private/tmp/voicetrace-next-workspace-tests.XXXXXX)
sources=(Next/Sources/Core/*.swift Next/Sources/App/Workspace.swift Next/Sources/App/Recorder.swift Next/Sources/App/LegacyDiagnostics.swift Sources/Protocol.swift Sources/Configurations.swift Sources/MemoryCredentials.swift Sources/Services.swift Sources/Audio.swift)
mkdir -p "$output/Sources"
cp "${sources[@]}" Next/Tests/WorkspaceTests.swift "$output/Sources/"
swiftc -D PERSONAL_BUILD -swift-version 5 -parse-as-library -module-cache-path /private/tmp/voicetrace-module-cache "$output/Sources"/*.swift -lsqlite3 -framework SwiftUI -framework AppKit -framework AVFoundation -framework Security -framework LocalAuthentication -o "$output/check"
"$output/check" "$PWD"
