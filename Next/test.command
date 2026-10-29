#!/bin/zsh
set -eu
cd "${0:A:h}/.."
output=$(mktemp -d /private/tmp/voicetrace-next-tests.XXXXXX)
mkdir -p "$output/Sources"
cp Next/Sources/Core/*.swift Next/Tests/CoreTests.swift "$output/Sources/"
swiftc -swift-version 5 -parse-as-library -module-cache-path /private/tmp/voicetrace-module-cache "$output/Sources"/*.swift -lsqlite3 -o "$output/check"
"$output/check" "$PWD"
