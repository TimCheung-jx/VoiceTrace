#!/bin/zsh
set -eu
cd "${0:A:h}"
testDir=$(mktemp -d /private/tmp/voicetrace-tests.XXXXXX)
cp Sources/*.swift Tests/*.swift "$testDir/"
core=("$testDir/Protocol.swift" "$testDir/Summary.swift")
common=(-swift-version 5 -parse-as-library -module-cache-path /private/tmp/voicetrace-module-cache)
for name in Protocol Summary; do
 swiftc "${common[@]}" "${core[@]}" "$testDir/${name}Tests.swift" -o "$testDir/check-$name"
 "$testDir/check-$name"
done
swiftc "${common[@]}" "$testDir/MemoryCredentials.swift" "$testDir/CredentialTests.swift" -o "$testDir/check-cache"
"$testDir/check-cache"
swiftc "${common[@]}" "${core[@]}" "$testDir/Configurations.swift" "$testDir/MemoryCredentials.swift" "$testDir/Services.swift" "$testDir/SettingsTests.swift" -o "$testDir/check-settings"
"$testDir/check-settings"

sed '/^struct NativeShareButton/,$d' "$testDir/Sharing.swift" > "$testDir/ExportCore.swift"
swiftc "${common[@]}" "$testDir/Protocol.swift" "$testDir/ExportCore.swift" "$testDir/ExportTests.swift" -framework AppKit -framework PDFKit -o "$testDir/check-export"
"$testDir/check-export"
modelSources=()
for name in Protocol Summary Configurations MemoryCredentials Services Audio Model Sharing Demo; do modelSources+=("$testDir/$name.swift"); done
swiftc "${common[@]}" "${modelSources[@]}" "$testDir/ModelTests.swift" -framework SwiftUI -framework AppKit -framework AVFoundation -framework PDFKit -framework Security -framework LocalAuthentication -o "$testDir/check-model"
"$testDir/check-model"

swiftc "${common[@]}" "${modelSources[@]}" "$testDir/ScenarioTests.swift" -framework SwiftUI -framework AppKit -framework AVFoundation -framework PDFKit -framework Security -framework LocalAuthentication -o "$testDir/check-scenarios"
"$testDir/check-scenarios"

swiftc "${common[@]}" -D PERSONAL_BUILD "${core[@]}" "$testDir/Configurations.swift" "$testDir/PersonalConfigTests.swift" -o "$testDir/check-personal"
"$testDir/check-personal"

swiftc "${common[@]}" "$testDir/Styles.swift" "$testDir/DesignTests.swift" -framework SwiftUI -framework AppKit -o "$testDir/check-design"
"$testDir/check-design"
