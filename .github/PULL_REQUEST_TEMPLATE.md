## Summary

<!-- What changed, and why is this the smallest correct change? -->

## User-visible behavior

<!-- Include before/after screenshots for interface changes. Write “None” when appropriate. -->

## Safety and distribution boundaries

- [ ] Wake assertions still start only after explicit user action and are released on Off/expiry/termination.
- [ ] The App Store product remains sandboxed and contains no Sparkle or alternate updater.
- [ ] No credential, profile, certificate, private key, build output, or user data is committed.
- [ ] New user-visible strings are complete in all eight localizations with matching format placeholders.
- [ ] Privacy, App Review notes, and metadata are updated if behavior or data handling changed.

## Verification

<!-- Paste the exact commands and outcomes; distinguish local results from GitHub checks. -->

- [ ] `./scripts/verify-release-assets.sh`
- [ ] `MacCoffeeTests`
- [ ] Relevant `MacCoffeeUITests` on an unlocked desktop
- [ ] Direct and App Store builds
- [ ] `./scripts/verify-bundles.sh`
- [ ] `zsh -n scripts/*.sh`

## Risks and rollback

<!-- Identify residual risk, untested hardware/account state, and the rollback path. -->

## Related issues

<!-- Use “Closes #…” when this PR should close an issue. -->
