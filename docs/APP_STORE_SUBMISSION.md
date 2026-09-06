# App Store Submission Guide

This guide prepares Mac Coffee for App Store Connect. It does not replace Apple's current signing, privacy, screenshot, or review requirements.

## Required account material

- An active Apple Developer Program membership.
- A Developer Team with access to the `com.rekurt.maccoffee` App ID.
- Apple Distribution signing identity and a Mac App Store distribution profile.
- A matching App Store Connect app record, agreements, tax, and banking status.
- Privacy answers consistent with [`PRIVACY.md`](../PRIVACY.md): no data collected.

No certificate, profile, Team ID, or App Store Connect credential belongs in this repository.

## Source preflight

```sh
brew bundle
xcodegen generate
./scripts/generate-screenshots.sh
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
```

Run `MacCoffeeUITests` on an unlocked interactive desktop. Check all eight explicit UI languages plus System mode, long strings, `⌘Q` cancellation/confirmation, timers, and both wake modes. App Store metadata and screenshots are maintained for English, Russian, and Simplified Chinese.

## Archive and inspect

```sh
MACCOFFEE_APP_STORE_TEAM=YOUR_TEAM_ID ./scripts/archive-app-store.sh
```

The archive script rejects Sparkle, `SUFeedURL`, MCP helpers/brokers/symbols, missing sandbox entitlement, `get-task-allow`, missing UI localizations, a non-universal executable, invalid signatures, or missing Hardened Runtime. Inspect the resulting archive in Xcode Organizer, validate it, and upload only after every local gate passes.

## App Store Connect

1. Copy the localized files under `metadata/en-US`, `metadata/ru`, and `metadata/zh-Hans` into the matching App Store Connect locales. English is the default storefront language.
2. Upload the two 1280×800 opaque PNG files from each locale's `screenshots` directory in their numbered order.
3. Use [`APP_STORE_REVIEW_NOTES.md`](APP_STORE_REVIEW_NOTES.md) as the basis for Review Notes.
4. Confirm the version, build number, age rating, category, privacy URL, support URL, and encryption/export-compliance answers.
5. Test the uploaded build with TestFlight on both Apple silicon and Intel hardware when available.
6. Submit manually and retain the validation and review correspondence with the release record.

## Current external blockers

A source tree can be release-ready without being upload-ready. A real App Store archive requires signing identities, profiles, Team access, and App Store Connect state outside Git. Never replace those checks with ad-hoc signing or publish a locally built test artifact as an App Store candidate.
