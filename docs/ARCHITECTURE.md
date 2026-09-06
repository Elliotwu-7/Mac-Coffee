# Mac Coffee Architecture

Mac Coffee is a native SwiftUI menu-bar application with two deliberately different distribution products. It never changes persistent system power settings or installs a privileged helper. The Direct product embeds an unprivileged, opt-in stdio MCP helper; the App Store product is compiled from an MCP-free core.

## Runtime flow

1. A Direct or App Store composition root creates exactly one `AppEnvironment` and one `LocalizationController`.
2. `AppModel` owns the visible session state and coordinates the platform adapters.
3. A user selects Off, Keep Mac Awake, or Keep Display Awake and a duration.
4. `IOKitPowerAssertionManager` creates or releases a process-owned IOKit assertion.
5. `SessionScheduler` ends finite sessions. Battery and lifecycle adapters deliver event-driven changes.
6. Termination preparation cancels the schedule, stops observers, shuts down the optional MCP endpoint, and releases all assertions.

No selected wake mode is restored at launch. Preferences contain language, duration, battery threshold, Launch at Login intent, notification authorization state, the last announced update version, and whether the user enabled MCP. Trusted MCP credentials live in Keychain; the bounded activity view is memory-only.

## Modules

| Module | Boundary |
| --- | --- |
| `Sources/Core/Domain` | Modes, durations, wake-session, and battery value types |
| `Sources/Core/Localization` | Supported languages and runtime bundle selection |
| `Sources/Core/Policy` | Low-battery threshold and hysteresis policy |
| `Sources/Core/Services` | Service protocols plus IOKit, IOPowerSources, scheduling, lifecycle, notifications, settings, and Launch at Login adapters |
| `Sources/Core/State` | `AppEnvironment`, `AppModel`, and coordinated quit state |
| `Sources/Core/Views` | Shared SwiftUI menu-bar panel, Settings, About, and application commands |
| `Sources/Core/MCP` | Versioned command/resource contract, authentication types, status snapshots, idempotency, and bounded activity |
| `Sources/Direct` | Direct entry point, Sparkle adapter, MCP lifecycle, pairing/settings UI, and safe client-configuration planners |
| `Sources/MCPHelper` | Embedded stdio MCP server built on the official Swift MCP SDK |
| `Sources/MCPBroker` | Embedded XPC service that brokers a running app endpoint to the stdio helper |
| `Sources/AppStore` | Sandboxed App Store entry point compiled against `MacCoffeeAppStoreCore`, with no alternate updater or MCP |
| `Tools/Screenshots` | Developer-only deterministic renderer that embeds the production views; not a dependency of either product |

Platform dependencies are injected through the focused protocols in `Sources/Core/Services`. Tests and screenshot tooling replace them with in-memory adapters; production composition roots supply the concrete AppKit, IOKit, UserNotifications, and ServiceManagement implementations.

## State and safety invariants

- A confirmed Off transition releases every active or pending Mac Coffee IOKit assertion.
- In steady state, one active wake assertion represents the selected mode. A mode change creates the replacement before releasing the old assertion so protection is not interrupted.
- If releasing a replaced assertion fails, the new assertion remains the confirmed mode, the stale assertion is tracked for retry, and a typed localizable notice is shown. Later transitions and termination retry all tracked releases.
- Timer expiry and low-battery protection turn the app Off before notifying the user.
- User cancellation of quit changes no session state.
- Confirmed quit and noninteractive system termination share idempotent cleanup.
- Manual Sleep, lid closure, shutdown, restart, thermal protection, and other macOS policy remain authoritative.

## Localization

`LocalizationController` is the single runtime string source. The stored language is either System or one of eight supported localizations. System mode follows the first supported macOS preferred language and falls back to English. Explicit selection resolves the matching `.lproj` from the app bundle's resources directory and updates all observing SwiftUI views without restarting or recreating an active assertion.

Localized user-visible failures are represented by `AppStatusNotice`, not preformatted stored strings, so an already-open notice changes language with the rest of the interface. Delivered macOS notifications are immutable; later notifications use the current language.

## Updates

Sparkle exists only in the Direct product. Scheduled checks use Sparkle's gentle-update delegate: the app records an available version, shows one localized card in the menu-bar panel, and sends at most one system notification per version when the panel is closed. The panel footer never contains an update control. Manual checks live in Settings and may focus Sparkle's standard update UI. Dismissing the card does not change an active wake session.

## MCP boundary

The optional Direct-only MCP path is `stdio client → MacCoffeeMCP helper → MacCoffeeMCPBroker.xpc → per-launch app XPC endpoint → MCPControlService → AppModel`. The helper never launches the app. The app registers an anonymous endpoint only while MCP is enabled and unregisters it during disable or termination.

New clients authenticate with a P-256 challenge-response and require explicit approval. Trust is stored in Keychain and bound to the observed code identity. Connections are limited to the current effective user; the broker validates peer location and signing identity. Mutating requests support a per-client `requestId` cache so retries do not apply the same action twice. The pairing coordinator bounds incomplete challenges (64 for 120 seconds), distinct pending approvals (32), and recent nonce/replay history (1,024). The App Store core excludes the entire `MCP` source group, and bundle verification rejects helper/broker artifacts or MCP symbols in that product.

## Distribution boundary

The products intentionally differ:

| Capability | Direct | App Store |
| --- | ---: | ---: |
| App Sandbox | No | Yes |
| Sparkle | Yes | No |
| Embedded MCP helper and broker | Optional, disabled by default | No |
| `SUFeedURL` | Required for an official release | Forbidden |
| Developer ID + notarization | Required | No |
| App Store distribution profile | No | Required |

`scripts/verify-bundles.sh` enforces this boundary on built applications. `scripts/archive-app-store.sh` repeats the critical checks on the signed archive before it is considered uploadable.

## Generated project

`project.yml` is the source of truth for `MacCoffee.xcodeproj`. Run `xcodegen generate` after changing targets, resources, build settings, or schemes, and commit both the YAML change and generated project diff.
