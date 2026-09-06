# Mac Coffee MCP integration

**English** · [Русский](MCP.ru.md) · [简体中文](MCP.zh-Hans.md)

Mac Coffee Direct includes a local Model Context Protocol server for controlling the running app from Codex, Claude Desktop, or another stdio MCP client. The integration is optional, disabled by default, and is not present in the Mac App Store product.

## Quick setup

1. Install and launch the Direct build of Mac Coffee.
2. Open **Settings → AI & automation**.
3. Enable the MCP integration.
4. Choose **Set up an MCP client**.
5. Select Codex, Claude Desktop, or Generic stdio.
6. Review the configuration path, embedded helper path, and exact proposed diff.
7. Confirm installation, then restart the selected MCP client.
8. Make the first MCP request and approve its pairing request in Mac Coffee.

The setup wizard refuses ambiguous or unsafe automatic edits. It preserves unrelated configuration, validates the resulting document, creates a timestamped backup when replacing an existing file, and falls back to copyable manual instructions for malformed files, conflicting entries, symlinks, or non-writable destinations.

## Client configuration

The executable is embedded inside the installed application:

```text
/Applications/Mac Coffee.app/Contents/Helpers/MacCoffeeMCP
```

Use the path shown by the setup wizard if Mac Coffee is installed elsewhere.

### Codex

The wizard updates `~/.codex/config.toml` with:

```toml
[mcp_servers.mac_coffee]
command = "/Applications/Mac Coffee.app/Contents/Helpers/MacCoffeeMCP"
```

### Claude Desktop

The wizard merges a `mac-coffee` entry into `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "mac-coffee": {
      "command": "/Applications/Mac Coffee.app/Contents/Helpers/MacCoffeeMCP",
      "args": []
    }
  }
}
```

### Other stdio clients

Configure a local stdio MCP server whose command is the embedded `MacCoffeeMCP` executable and whose arguments list is empty. Mac Coffee must already be running; the helper deliberately does not launch it.

## Tools

The server uses strict JSON schemas. Unknown fields and unsupported enum values are rejected.

| Tool | Arguments | Result |
| --- | --- | --- |
| `maccoffee_get_status` | none | Current mode, session, battery, preferences, and capabilities |
| `maccoffee_set_session` | `mode`, `duration`, optional `requestId` | Starts or replaces a wake session |
| `maccoffee_stop_session` | optional `requestId` | Stops the active session and releases its assertion |
| `maccoffee_set_battery_threshold` | `percent` 10–30, optional `requestId` | Changes the low-battery cutoff |
| `maccoffee_set_launch_at_login` | `enabled`, optional `requestId` | Changes Launch at Login |
| `maccoffee_set_language` | `language`, optional `requestId` | Changes the interface language immediately |

`mode` accepts `system` or `display`. Use `maccoffee_stop_session` rather than passing `off`.

`duration` accepts `minutes30`, `hours1`, `hours2`, `hours4`, `hours8`, or `indefinite`.

`language` accepts `system`, `en`, `ru`, `de`, `fr`, `zh-Hans`, `ja`, `ko`, or `es`.

For mutating calls, a client may supply a stable `requestId` of at most 128 characters. Repeating the same request from the same paired client returns the cached result rather than applying the change twice.

Example arguments:

```json
{
  "mode": "system",
  "duration": "hours2",
  "requestId": "focus-session-2026-08-31"
}
```

## Resources

| URI | Purpose |
| --- | --- |
| `maccoffee://status` | Versioned snapshot of the current application state |
| `maccoffee://capabilities` | Supported tools, enum values, and contract information |
| `maccoffee://activity` | Bounded in-memory activity entries for paired clients |

Status subscriptions are supported. The server publishes debounced updates when relevant application state changes.

## Security model

- The MCP integration is off until the user enables it.
- The stdio helper, XPC broker, and application service are embedded in the Direct app bundle.
- XPC connections are restricted to the current effective macOS user.
- Broker peers are validated by executable location and code-signing identity.
- A new client completes a P-256 challenge-response flow and requires explicit approval in Mac Coffee.
- Incomplete challenges expire after 120 seconds; challenges, pending approvals, and replay history all have fixed memory bounds.
- Trusted client credentials are stored in Keychain and bound to the observed code identity.
- A user can revoke a client immediately or forget its stored relationship in Settings.
- Mutating commands are refused while the app is handling a conflicting local transition.
- MCP never bypasses battery protection or macOS power and safety decisions.
- The App Store build is compiled from a separate core and contains no MCP helper, broker, settings, or MCP symbols.

MCP activity is bounded, kept in memory, and not transmitted. It is cleared when Mac Coffee terminates.

## Troubleshooting

### Client reports that Mac Coffee is unavailable

- Launch Mac Coffee before using the MCP server.
- Confirm that MCP is enabled and its status is Ready in Settings.
- If Mac Coffee was moved, rerun the setup wizard so the client points to the current embedded helper.

### Approval required or client unpaired

Open Mac Coffee Settings and approve the pending pairing request. Confirm the displayed client name and signing identity before approving.

### Client was updated and no longer connects

Code identity changes are not silently accepted. Revoke or forget the old client entry, then pair the updated client again.

### The setup wizard offers manual instructions

The current configuration is malformed, contains a conflicting Mac Coffee entry, is a symlink, or cannot be safely replaced. Copy the generated block and merge it manually; the wizard intentionally leaves the original file untouched.

### Remove the integration

1. Disable MCP in Mac Coffee Settings.
2. Remove the `mac_coffee` table from Codex or the `mac-coffee` object from Claude Desktop.
3. Restart the MCP client.
4. Optionally forget trusted clients in Mac Coffee Settings.

Disabling MCP closes active integration connections and unregisters the app endpoint from the local broker.
