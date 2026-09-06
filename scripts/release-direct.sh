#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

required=(
  MACCOFFEE_DEVELOPER_ID
  MACCOFFEE_NOTARY_PROFILE
  MACCOFFEE_APPCAST_URL
  MACCOFFEE_SPARKLE_PRIVATE_KEY_FILE
)
for key in $required; do
  [[ -n "${(P)key:-}" ]] || {
    print -u2 "Missing required release setting: $key"
    exit 64
  }
done
[[ "$MACCOFFEE_APPCAST_URL" == https://* ]] || {
  print -u2 "MACCOFFEE_APPCAST_URL must use HTTPS."
  exit 65
}
[[ -f "$MACCOFFEE_SPARKLE_PRIVATE_KEY_FILE" ]] || {
  print -u2 "Sparkle private key file not found."
  exit 66
}

cd "$ROOT_DIR"
"$SCRIPT_DIR/verify-release-assets.sh"
marketing_version=$(/usr/bin/awk -F ' = ' '/^MARKETING_VERSION = / { print $2 }' Config/Shared.xcconfig)
[[ -n "$marketing_version" ]] || {
  print -u2 "MARKETING_VERSION is missing from Config/Shared.xcconfig."
  exit 65
}
if [[ -n "${GITHUB_REF_NAME:-}" && "$GITHUB_REF_NAME" != "v$marketing_version" ]]; then
  print -u2 "Release tag $GITHUB_REF_NAME does not match v$marketing_version."
  exit 65
fi
xcodegen generate
release_dir="$ROOT_DIR/dist/release"
archive_path="$release_dir/MacCoffee.xcarchive"
export_dir="$release_dir/export"
derived_dir="$ROOT_DIR/build/release-direct"
/bin/mkdir -p "$release_dir"
/bin/rm -rf "$archive_path" "$export_dir" "$derived_dir"

public_key=$(/usr/bin/swift -e '
import CryptoKit
import Foundation
let text = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
guard let secret = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    FileHandle.standardError.write(Data("Sparkle key is not valid Base64.\n".utf8))
    exit(65)
}
if secret.count == 32 {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: secret)
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else if secret.count == 96 {
    print(secret.suffix(32).base64EncodedString())
} else {
    FileHandle.standardError.write(Data("Invalid Sparkle key length.\n".utf8))
    exit(65)
}
' "$MACCOFFEE_SPARKLE_PRIVATE_KEY_FILE")

xcodebuild archive \
  -project MacCoffee.xcodeproj \
  -scheme MacCoffeeDirect \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_dir" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$MACCOFFEE_DEVELOPER_ID" \
  MACCOFFEE_APPCAST_URL="$MACCOFFEE_APPCAST_URL" \
  MACCOFFEE_SPARKLE_PUBLIC_KEY="$public_key"

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_dir" \
  -exportOptionsPlist "$ROOT_DIR/ExportOptions/DeveloperID.plist"

app_path="$export_dir/Mac Coffee.app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
/usr/bin/lipo "$app_path/Contents/MacOS/Mac Coffee" -verify_arch arm64 x86_64
[[ -d "$app_path/Contents/Frameworks/Sparkle.framework" ]] || {
  print -u2 "Direct archive does not contain Sparkle."
  exit 65
}
[[ -f "$app_path/Contents/Resources/PrivacyInfo.xcprivacy" ]] || {
  print -u2 "Direct archive is missing PrivacyInfo.xcprivacy."
  exit 65
}
for locale in de en es fr ja ko ru zh-Hans; do
  [[ -f "$app_path/Contents/Resources/$locale.lproj/Localizable.strings" ]] || {
    print -u2 "Direct archive is missing $locale localization."
    exit 65
  }
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app_path/Contents/Info.plist")" == https://* ]] || {
  print -u2 "Direct archive does not expose an HTTPS Sparkle feed."
  exit 65
}
runtime_targets=(
  "$app_path"
  "$app_path/Contents/Helpers/MacCoffeeMCP"
  "$app_path/Contents/XPCServices/MacCoffeeMCPBroker.xpc"
)
for runtime_target in "$runtime_targets[@]"; do
  if ! /usr/bin/codesign -dvv "$runtime_target" 2>&1 | /usr/bin/grep -q 'flags=.*runtime'; then
    print -u2 "$runtime_target does not have Hardened Runtime enabled."
    exit 65
  fi
done
entitlements_file=$(/usr/bin/mktemp -t maccoffee-direct-entitlements)
/usr/bin/codesign -d --entitlements - --xml "$app_path" > "$entitlements_file" 2>/dev/null
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$entitlements_file" >/dev/null 2>&1; then
  print -u2 "Direct archive contains the debug get-task-allow entitlement."
  exit 65
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements_file" >/dev/null 2>&1; then
  print -u2 "Direct archive unexpectedly enables App Sandbox."
  exit 65
fi
/bin/rm -f "$entitlements_file"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
notary_zip="$release_dir/MacCoffee-$version-notary.zip"
/bin/rm -f "$notary_zip"
/usr/bin/ditto -c -k --keepParent "$app_path" "$notary_zip"
notary_options=(--keychain-profile "$MACCOFFEE_NOTARY_PROFILE")
if [[ -n "${MACCOFFEE_NOTARY_KEYCHAIN:-}" ]]; then
  notary_options+=(--keychain "$MACCOFFEE_NOTARY_KEYCHAIN")
fi
xcrun notarytool submit "$notary_zip" "${notary_options[@]}" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"

export MACCOFFEE_APP_PATH="$app_path"
export MACCOFFEE_DMG_PATH="$release_dir/MacCoffee-$version.dmg"
export MACCOFFEE_SIGN_IDENTITY="$MACCOFFEE_DEVELOPER_ID"
"$SCRIPT_DIR/package-dmg.sh"

xcrun notarytool submit "$MACCOFFEE_DMG_PATH" "${notary_options[@]}" --wait
xcrun stapler staple "$MACCOFFEE_DMG_PATH"
xcrun stapler validate "$MACCOFFEE_DMG_PATH"
/usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$MACCOFFEE_DMG_PATH"

export MACCOFFEE_APPCAST_OUTPUT_DIR="$release_dir"
export MACCOFFEE_GENERATE_APPCAST=$(/usr/bin/find "$derived_dir/SourcePackages/artifacts" \
  -type f -path '*/bin/generate_appcast' -perm -111 -print -quit)
"$SCRIPT_DIR/generate-appcast.sh"

(
  cd "$release_dir"
  /usr/bin/shasum -a 256 "${MACCOFFEE_DMG_PATH:t}" > "${MACCOFFEE_DMG_PATH:t}.sha256"
)

print "Release artifacts and signed appcast are ready in: $release_dir"
