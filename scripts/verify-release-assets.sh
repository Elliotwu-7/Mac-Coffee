#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
locales=(en-US ru zh-Hans)
bundle_locales=(de en es fr ja ko ru zh-Hans)
metadata_files=(
  description.txt keywords.txt marketing_url.txt name.txt privacy_url.txt
  promotional_text.txt release_notes.txt subtitle.txt support_url.txt
)

fail() {
  print -u2 "Release asset verification failed: $1"
  exit 65
}

trimmed_file() {
  /usr/bin/sed -e 's/[[:space:]]*$//' "$1" | /usr/bin/awk '
    BEGIN { first = 1 }
    /^[[:space:]]*$/ && first { next }
    { first = 0; lines[++count] = $0 }
    END {
      while (count > 0 && lines[count] ~ /^[[:space:]]*$/) count--
      for (line_number = 1; line_number <= count; line_number++) print lines[line_number]
    }
  '
}

character_count() {
  LC_ALL=en_US.UTF-8 /usr/bin/wc -m < "$1" | /usr/bin/tr -d ' '
}

byte_count() {
  LC_ALL=C /usr/bin/wc -c < "$1" | /usr/bin/tr -d ' '
}

for plist in "$ROOT_DIR/Resources/Direct/Info.plist" "$ROOT_DIR/Resources/AppStore/Info.plist"; do
  /usr/bin/plutil -lint "$plist" >/dev/null
  declared=()
  index=0
  while value=$(/usr/libexec/PlistBuddy -c "Print :CFBundleLocalizations:$index" "$plist" 2>/dev/null); do
    declared+=("$value")
    (( index += 1 ))
  done
  [[ "${(j:,:)declared}" == "${(j:,:)bundle_locales}" ]] || {
    fail "$plist does not declare the canonical eight-localization set"
  }
done

for locale in "$locales[@]"; do
  directory="$ROOT_DIR/metadata/$locale"
  [[ -d "$directory" ]] || fail "missing metadata directory $locale"

  for filename in "$metadata_files[@]"; do
    file="$directory/$filename"
    [[ -s "$file" ]] || fail "missing or empty $locale/$filename"
    value="$(trimmed_file "$file")"
    [[ -n "$value" ]] || fail "blank $locale/$filename"
  done

  (( $(character_count "$directory/name.txt") <= 30 )) || fail "$locale/name.txt exceeds 30 characters"
  (( $(character_count "$directory/subtitle.txt") <= 30 )) || fail "$locale/subtitle.txt exceeds 30 characters"
  (( $(character_count "$directory/description.txt") <= 4000 )) || fail "$locale/description.txt exceeds 4000 characters"
  (( $(character_count "$directory/promotional_text.txt") <= 170 )) || fail "$locale/promotional_text.txt exceeds 170 characters"
  (( $(byte_count "$directory/keywords.txt") <= 100 )) || fail "$locale/keywords.txt exceeds 100 bytes"

  for filename in marketing_url.txt privacy_url.txt support_url.txt; do
    [[ "$(trimmed_file "$directory/$filename")" == https://* ]] || fail "$locale/$filename must use HTTPS"
  done

  for filename in 01-menu-bar.png 02-settings.png; do
    screenshot="$directory/screenshots/$filename"
    [[ -s "$screenshot" ]] || fail "missing screenshot $locale/$filename"
    width=$(/usr/bin/sips -g pixelWidth "$screenshot" | /usr/bin/awk '/pixelWidth/ { print $2 }')
    height=$(/usr/bin/sips -g pixelHeight "$screenshot" | /usr/bin/awk '/pixelHeight/ { print $2 }')
    alpha=$(/usr/bin/sips -g hasAlpha "$screenshot" | /usr/bin/awk '/hasAlpha/ { print $2 }')
    [[ "$width" == 1280 && "$height" == 800 ]] || fail "$locale/$filename must be 1280x800"
    [[ "$alpha" == no ]] || fail "$locale/$filename must be opaque"
  done
done

actual_metadata_locales=("${(@f)$(
  /usr/bin/find "$ROOT_DIR/metadata" -mindepth 1 -maxdepth 1 -type d -exec /usr/bin/basename {} \; \
    | LC_ALL=C /usr/bin/sort
)}")
[[ "${(j:,:)actual_metadata_locales}" == "${(j:,:)locales}" ]] || {
  fail "metadata must contain only en-US, ru, and zh-Hans"
}

for localization in "$ROOT_DIR"/Resources/Shared/*.lproj/Localizable.strings; do
  /usr/bin/plutil -lint "$localization" >/dev/null
done

/usr/bin/xcrun swift - "$ROOT_DIR/Resources/Shared" <<'SWIFT'
import Foundation

let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let localeIdentifiers = ["de", "en", "es", "fr", "ja", "ko", "ru", "zh-Hans"]
let placeholderRegex = try! NSRegularExpression(pattern: #"%(?:[0-9]+\$)?(?:@|d)"#)

func load(_ identifier: String) throws -> [String: String] {
    let url = resources
        .appendingPathComponent("\(identifier).lproj", isDirectory: true)
        .appendingPathComponent("Localizable.strings")
    let data = try Data(contentsOf: url)
    guard let values = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: String]
    else {
        throw NSError(domain: "MacCoffeeReleaseAssets", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Invalid strings dictionary: \(url.path)"
        ])
    }
    return values
}

func placeholders(in value: String) -> [String] {
    let range = NSRange(value.startIndex..., in: value)
    return placeholderRegex.matches(in: value, range: range).compactMap {
        Range($0.range, in: value).map { String(value[$0]) }
    }
}

do {
    let reference = try load("en")
    for identifier in localeIdentifiers {
        let candidate = try load(identifier)
        guard Set(candidate.keys) == Set(reference.keys) else {
            let missing = Set(reference.keys).subtracting(candidate.keys).sorted()
            let extra = Set(candidate.keys).subtracting(reference.keys).sorted()
            throw NSError(domain: "MacCoffeeReleaseAssets", code: 2, userInfo: [
                NSLocalizedDescriptionKey:
                    "Localization key mismatch in \(identifier): missing=\(missing), extra=\(extra)"
            ])
        }
        for key in reference.keys.sorted() {
            let expected = placeholders(in: reference[key]!)
            let actual = placeholders(in: candidate[key]!)
            guard actual == expected else {
                throw NSError(domain: "MacCoffeeReleaseAssets", code: 3, userInfo: [
                    NSLocalizedDescriptionKey:
                        "Format placeholder mismatch in \(identifier) for \(key): \(actual) != \(expected)"
                ])
            }
        }
    }
} catch {
    FileHandle.standardError.write(Data("Release asset verification failed: \(error.localizedDescription)\n".utf8))
    exit(65)
}
SWIFT

expected_attribution='Forked from [Elliotwu-7/Mac-Coffee](https://github.com/Elliotwu-7/Mac-Coffee).'
[[ "$(trimmed_file "$ROOT_DIR/README.md" | /usr/bin/tail -n 1)" == "$expected_attribution" ]] || {
  fail "README.md must end with the canonical upstream attribution"
}

[[ ! -e "$ROOT_DIR/README.zh-CN.md" ]] || fail "obsolete README.zh-CN.md is still present"
[[ ! -e "$ROOT_DIR/docs/superpowers" ]] || fail "internal agent planning artifacts are still present"
[[ ! -e "$ROOT_DIR/.superdesign" ]] || fail "local design workspace is still present"
for readme in README.md README.ru.md README.zh-Hans.md; do
  [[ -s "$ROOT_DIR/$readme" ]] || fail "missing localized $readme"
done

actual_readmes=("${(@f)$(
  /usr/bin/find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type f -name 'README*.md' \
    -exec /usr/bin/basename {} \; | LC_ALL=C /usr/bin/sort
)}")
expected_readmes=(README.md README.ru.md README.zh-Hans.md)
[[ "${(j:,:)actual_readmes}" == "${(j:,:)expected_readmes}" ]] || {
  fail "repository documentation must contain only English, Russian, and Simplified Chinese READMEs"
}

print "Verified App Store metadata, localization parity, screenshots, and repository entry points."
