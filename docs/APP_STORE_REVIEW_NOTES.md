# Mac Coffee 2.0 — App Review Notes

## Purpose

Mac Coffee is a native menu-bar utility that prevents idle sleep only while the user explicitly enables a wake session. It can keep the Mac awake or keep both the Mac and display awake for 30 minutes, 1, 2, 4, or 8 hours, or indefinitely.

It does not override manual Sleep, lid closure, shutdown, restart, thermal protection, low-level system policy, or other macOS safety decisions.

## Suggested review flow

1. Launch Mac Coffee. It appears in the menu bar and always starts Off.
2. Open the menu-bar panel and choose **Keep Mac Awake** or **Keep Display Awake**.
3. Select a finite duration and observe the remaining-time label; select another duration to replace it without restarting the app.
4. Select **Off** and observe that the wake request ends immediately.
5. Open **Settings…**. Change the language; the panel, Settings, About, errors, accessibility labels, dialogs, and later notifications update immediately without changing the process or active wake session.
6. Adjust the battery cutoff between 10% and 30% (15% by default). A wake session stops at or below the threshold while on battery and must be re-enabled manually after recovery.
7. Enable Launch at Login if desired; this setting is opt-in.
8. Choose Quit or press `⌘Q`. Cancel preserves the active session; confirmation releases the assertion and exits.

System language follows the first supported macOS preferred language and falls back to English. Explicit languages are English, Russian, German, French, Simplified Chinese, Japanese, Korean, and Spanish.

## Platform APIs and privileges

- Wake sessions use the public process-owned `IOPMAssertionCreateWithName` API.
- Battery changes come from local IOPowerSources notifications.
- Launch at Login uses public `SMAppService` and changes only after an explicit user action.
- Local notifications report session expiry and low-battery stops.
- The app requests no administrator privileges and includes no helper, daemon, shell command, activity simulation, analytics, advertising, account, or backend.

## App Store boundary

The submitted `com.rekurt.maccoffee` product is sandboxed. It does not link or bundle Sparkle, declare `SUFeedURL`, expose any alternate update action, or contain the Direct edition's optional MCP helper, broker, settings, or symbols. A separate Direct product exists in source but is not submitted to App Review.

## Privacy

No data is collected or transmitted. Battery state and preferences remain on device. See <https://github.com/rekurt/Mac-Coffee/blob/main/PRIVACY.md>.
