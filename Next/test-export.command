#!/bin/zsh
set -eu
cd "${0:A:h}/.."
stage=$(mktemp -d /private/tmp/voicetrace-export-checks.XXXXXX)
cp Next/Sources/Core/*.swift Next/Sources/App/Exporter.swift Next/Tests/ExportChecks.swift "$stage/"
swiftc -swift-version 5 -parse-as-library -module-cache-path /private/tmp/voicetrace-module-cache "$stage"/*.swift -lsqlite3 -framework SwiftUI -framework AppKit -framework PDFKit -o "$stage/check"
"$stage/check" "$PWD"
