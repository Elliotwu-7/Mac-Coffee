# Security Policy

## Supported versions

Security fixes target the latest published Mac Coffee 2.x release and the current `main` branch. The original 1.x privileged-helper design is not supported by this fork; use the [legacy cleanup guide](LEGACY_CLEANUP.md) if it was previously installed.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's **Report a vulnerability** form in the repository Security tab:

<https://github.com/rekurt/Mac-Coffee/security/advisories/new>

Include affected versions, macOS version and architecture, Direct or App Store edition, reproduction steps, impact, and a minimal proof of concept. Remove credentials and unrelated personal information from logs. You may suggest a mitigation, but please allow coordinated disclosure before publishing details.

If private vulnerability reporting is unavailable, contact the maintainer through the private contact options on the [rekurt GitHub profile](https://github.com/rekurt).

## Security model

Mac Coffee uses public, process-owned IOKit assertions; no privileged helper, daemon, persistent `pmset` mutation, activity simulation, analytics, or backend is present. The Direct edition can contact its signed HTTPS Sparkle update feed for scheduled and manual checks. The sandboxed App Store edition contains no alternate updater.

The Direct edition also includes an optional local MCP integration. It is disabled by default, never launches Mac Coffee, and communicates through an embedded stdio helper and XPC services restricted to the current macOS user. New clients use a P-256 challenge-response and require explicit approval. Trusted credentials are stored in Keychain and bound to the observed code identity; access can be revoked immediately. MCP activity is bounded, retained only in memory, and never transmitted. The App Store product is built from an MCP-free core and bundle verification rejects MCP artifacts and symbols.

Authentication state is availability-bounded as well as authenticated: at most 64 incomplete challenges are retained for 120 seconds, at most 32 distinct pairing requests can await review, and nonce/replay histories are capped at 1,024 entries. Expired challenges are consumed and cannot be completed.

See [MCP integration](MCP.md) for the complete contract, pairing flow, configuration safety rules, and removal steps.
