#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
identity=${AWDL_SIGNING_IDENTITY:--}
team=${AWDL_TEAM_ID:-}
if [[ "$identity" == "-" && -n "$team" ]] ||
   [[ "$identity" != "-" && ! "$team" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Supply both AWDL_SIGNING_IDENTITY and its 10-character AWDL_TEAM_ID." >&2
    exit 1
fi

mkdir -p .build
stage=$(mktemp -d "$PWD/.build/build.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/AWDL Switch.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Library/LaunchDaemons" "$contents/Resources" "$stage/AppIcon.iconset"
cp Bundle/Info.plist "$contents/Info.plist"
cp Bundle/com.andreakaus.awdlswitch.helper.plist "$contents/Library/LaunchDaemons/"

team_value=nil
if [[ -n "$team" ]]; then team_value="\"$team\""; fi
cat > "$stage/BuildSigning.swift" <<SWIFT
enum BuildSigning {
    static let teamID: String? = $team_value
}
SWIFT

swift_flags=(-target "$(uname -m)-apple-macos13.0" -module-cache-path "$PWD/.build/module-cache" -O -warnings-as-errors)
xcrun swiftc "${swift_flags[@]}" -o "$stage/generate-icon" Sources/Artwork/*.swift
"$stage/generate-icon" "$stage/AppIcon.iconset"
/usr/bin/iconutil -c icns -o "$contents/Resources/AppIcon.icns" "$stage/AppIcon.iconset"
xcrun swiftc "${swift_flags[@]}" -o "$contents/MacOS/AWDLSwitchHelper" \
    "$stage/BuildSigning.swift" Sources/Shared/*.swift Sources/Helper/*.swift
xcrun swiftc "${swift_flags[@]}" -o "$contents/MacOS/AWDLSwitch" \
    "$stage/BuildSigning.swift" Sources/Shared/*.swift Sources/Artwork/CircuitSwitch.swift Sources/App/*.swift

sign_flags=(--sign "$identity" --force --options runtime)
helper="$contents/MacOS/AWDLSwitchHelper"
codesign "${sign_flags[@]}" --identifier com.andreakaus.awdlswitch.helper "$helper"
codesign "${sign_flags[@]}" "$app"
codesign --verify --deep --strict "$app"

if [[ -n "$team" ]]; then
    requirement="anchor apple generic and certificate leaf[subject.OU] = \"$team\""
    codesign --verify -R "=$requirement and identifier \"com.andreakaus.awdlswitch\"" "$app"
    codesign --verify -R "=$requirement and identifier \"com.andreakaus.awdlswitch.helper\"" "$helper"
else
    # The installer places the helper and its client requirement in root-owned locations.
    client_hash=$(codesign -d --verbose=4 "$app" 2>&1 | sed -n 's/^CDHash=//p')
    [[ "$client_hash" =~ ^[a-f0-9]{40}$ ]] || { echo "Couldn’t read the app’s code signature." >&2; exit 1; }
    codesign --verify -R "=identifier \"com.andreakaus.awdlswitch\" and cdhash H\"$client_hash\"" "$app"

    payload="$stage/payload"
    label=com.andreakaus.awdlswitch.helper
    helper_location="/Library/PrivilegedHelperTools/$label"
    plist="$payload/Library/LaunchDaemons/$label.plist"
    mkdir -p "$payload/Applications" "$payload/Library/PrivilegedHelperTools" "$payload/Library/LaunchDaemons"
    ditto "$app" "$payload/Applications/AWDL Switch.app"
    install -m 755 "$helper" "$payload$helper_location"
    install -m 644 "Bundle/$label.plist" "$plist"
    /usr/libexec/PlistBuddy -c 'Delete :BundleProgram' \
        -c "Add :ProgramArguments array" -c "Add :ProgramArguments:0 string $helper_location" \
        -c 'Add :EnvironmentVariables dict' -c "Add :EnvironmentVariables:AWDL_CLIENT_CDHASH string $client_hash" \
        "$plist"
    plutil -lint "$plist"

    pkgbuild --analyze --root "$payload" "$stage/components.plist"
    /usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$stage/components.plist"
    pkgbuild --root "$payload" --component-plist "$stage/components.plist" --install-location / \
        --scripts Bundle/Installer --identifier com.andreakaus.awdlswitch.local \
        --version "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$contents/Info.plist")" \
        "$stage/AWDL Switch.pkg"
fi

output="$PWD/.build/AWDL Switch.app"
rm -rf "$output"
mv "$app" "$output"
echo "$output"
if [[ -z "$team" ]]; then
    package="$PWD/.build/AWDL Switch.pkg"
    mv -f "$stage/AWDL Switch.pkg" "$package"
    echo "$package"
fi
