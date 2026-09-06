# Mac Coffee 2.0 Release Checklist

Use this checklist for each candidate. Check a gate only from fresh evidence for the exact commit being released. A local ad-hoc build or DMG is never an official release artifact.

## Source and automated gates

- [ ] Working tree contains only intentional release files; no credentials, logs, archives, DerivedData, agent notes, or obsolete duplicate assets.
- [ ] `xcodegen generate` produces no unexpected project diff.
- [ ] `./scripts/verify-release-assets.sh` passes.
- [ ] `MacCoffeeTests` passes on the release commit.
- [ ] `MacCoffeeUITests` passes on an unlocked interactive desktop.
- [ ] Direct and App Store Release products build as universal `arm64`/`x86_64` applications.
- [ ] `./scripts/verify-bundles.sh` passes for both products.
- [ ] `zsh -n scripts/*.sh` passes.
- [ ] CodeQL passes for the release commit.
- [ ] Dependency review contains no unresolved release-blocking vulnerability.

## Functional matrix

- [ ] App always launches Off and leaves no assertion until explicit activation.
- [ ] Off, Keep Mac Awake, and Keep Display Awake behave correctly.
- [ ] 30-minute, 1-, 2-, 4-, and 8-hour sessions and indefinite sessions behave correctly.
- [ ] Replacing a duration updates the current session; expiry releases the assertion.
- [ ] Battery protection stops/blocks at every supported boundary and does not flap around the threshold.
- [ ] Launch at Login is opt-in and accurately reports unavailable or approval-required states.
- [ ] Settings, About, local notifications, and error notices match each distribution product.
- [ ] Direct manual update check appears only in Settings; an available version shows one localized panel card and at most one system notification per version when the panel is closed.
- [ ] Footer Quit and `⌘Q` share one dialog; Cancel preserves state; Confirm exits after cleanup.
- [ ] Logout, shutdown, and termination cleanup is noninteractive and idempotent.
- [ ] `pmset -g assertions` shows the expected IOKit type while active and no Mac Coffee assertion after Off or termination.

## Localization and accessibility

- [ ] System language works for supported languages and falls back to English otherwise.
- [ ] English, Russian, German, French, Simplified Chinese, Japanese, Korean, and Spanish pass the same UI scenario.
- [ ] Language changes immediately without a PID or wake-session change and persists after relaunch.
- [ ] No panel, Settings, About, dialog, notification preview, or accessibility label is clipped or untranslated.
- [ ] Localization keys and `%d`/`%@` placeholders are identical in all `.strings` files.
- [ ] All 6 tracked EN/RU/ZH-Hans App Store screenshots are regenerated, visually reviewed, 1280×800, and opaque.

## Direct release

- [ ] Developer ID certificate, notarization profile, HTTPS appcast URL, and Sparkle EdDSA private key are provided through secure release credentials.
- [ ] `./scripts/release-direct.sh` produces a Developer ID-signed, Hardened Runtime app and DMG.
- [ ] Apple notarization succeeds and tickets are stapled to both app and DMG.
- [ ] Gatekeeper accepts the app and DMG on a clean Mac.
- [ ] Sparkle appcast signature, version, minimum macOS version, URL, and SHA-256 are independently checked.
- [ ] Installed previous official version upgrades successfully to this candidate.
- [ ] MCP is disabled by default; Codex, Claude Desktop, and generic stdio setup paths are reviewed without overwriting unrelated client configuration.
- [ ] Pairing approval, trusted-client revoke/forget, idempotent request replay, status subscription, disable, and termination cleanup pass.
- [ ] Direct bundle contains the signed `MacCoffeeMCP` helper and `MacCoffeeMCPBroker.xpc`; both have the expected Team identity in an official build.

## App Store release

- [ ] Apple Distribution identity, Mac App Store profile, Team ID, and App Store Connect access are valid.
- [ ] `MACCOFFEE_APP_STORE_TEAM=… ./scripts/archive-app-store.sh` passes.
- [ ] Xcode Organizer validation succeeds with no unresolved warning.
- [ ] App Store privacy answers state no data collected and match `PrivacyInfo.xcprivacy` and `PRIVACY.md`.
- [ ] Localized metadata and screenshots are uploaded for en-US, ru, and zh-Hans; English is the default locale.
- [ ] TestFlight smoke passes on Apple silicon and Intel hardware when available.
- [ ] App Review notes accurately describe IOKit, battery protection, language switching, quit behavior, and the absence of Sparkle and MCP.

## Publication record

- [ ] Version and build numbers match source, archive, metadata, tag, and release notes.
- [ ] Tag points to the verified commit and is created only after all applicable gates pass.
- [ ] Published checksums match downloaded artifacts.
- [ ] Known limitations and any skipped hardware matrix are documented in the release record.
