# Contributing

Thank you for improving Mac Coffee. Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

```sh
git clone https://github.com/rekurt/Mac-Coffee.git
cd Mac-Coffee
brew bundle
xcodegen generate
```

Requirements are macOS 13 or later, a full Xcode installation, Homebrew, and the build tools in [`Brewfile`](../Brewfile). `project.yml` enforces the minimum supported XcodeGen version.

## Before opening a pull request

```sh
./scripts/verify-release-assets.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project MacCoffee.xcodeproj \
  -scheme MacCoffeeTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

./scripts/build-local.sh direct
./scripts/build-local.sh app-store
./scripts/verify-bundles.sh
zsh -n scripts/*.sh
```

Run `MacCoffeeUITests` on an unlocked desktop for UI, accessibility, language, or quit-flow changes. Regenerate screenshots when user-visible copy or layout changes:

```sh
./scripts/generate-screenshots.sh
```

Keep pull requests focused. Explain behavior and distribution-boundary changes, include tests, and attach before/after screenshots for UI work. `project.yml` is authoritative; commit the generated Xcode project after running XcodeGen.

## Issues

Search existing [issues](https://github.com/rekurt/Mac-Coffee/issues) before filing one. For bugs, include the Mac Coffee version or commit, macOS version, Mac architecture, Direct or App Store edition, active language, power source, expected behavior, exact reproduction steps, and relevant screenshots or Console excerpts with secrets removed.

Do not file vulnerabilities publicly. Follow the [security policy](SECURITY.md).

## Commit and code expectations

- Follow the existing Swift style and prefer small, explicit domain types.
- Add a failing regression test before fixing a bug.
- Preserve the Off-at-launch and guaranteed assertion-release invariants.
- Keep Sparkle out of the App Store target.
- Add every new user-visible string to all eight localization files and keep format placeholders identical.
- Never commit signing certificates, provisioning profiles, notarization credentials, Sparkle private keys, or generated build products.

Conventional Commit subjects are encouraged but not mandatory; a clear, imperative subject and explainable diff are mandatory.
