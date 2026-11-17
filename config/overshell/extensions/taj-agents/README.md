# OverShell agents on Taj

`TajAgents.cs` is a dotfiles-owned .NET 11 file-based app. OverShell hosts it using
its generic command-extension protocol. It receives agent snapshots on stdin and
publishes changes over one persistent Shubbak named-pipe connection.

## Configuration

The entry is `extensions["taj.agents"]` in `../../settings.jsonc`. The bar's sources,
colours, gestures and connected profile are in `../../../shubbak/shubbak.kdl`.

| Setting | Effect |
|---|---|
| `enabled` | Starts/stops the publisher, including while OverShell is running |
| `showIdle` | Show reviewed idle sessions; default false |
| `showExited` | Show exited agents; default false |
| `showUnknown` | Show detected agents whose state is not known yet; default true |
| `deduplicateSessions` | Count the same harness/session ID once across multiple views |
| `showCount` | Display `AI N`, the number of sessions passing the visibility filters |
| `showHarnessIcons` | Use OpenCode's two-tone icon, matching OverShell's tabs; default true |
| `iconColour` | Icon foreground as `#RRGGBB`; default `#cdd6f4` |
| `maxAgents` | Number of individual pills, 1–12; the configured default is 8 |
| `label` | `harness`, `project`, or `session`; the latter two add a shortened name |
| `labelLength` | Maximum added-name length, default 10 |
| `harnessLabels` | Initials/glyphs for harnesses without an icon, or when icons are disabled |
| `stateGlyphs` | The state symbols, independently configurable |

Saving display settings updates the running publisher. Set `enabled` false to stop
it and hide the zone. After editing/pulling the C# source, disable the extension,
run `Build.ps1`, and enable it again (save each settings change).

The current configuration launches a native build from
`{stateDir}/extensions/taj-agents/TajAgents.exe`; the source and build helper stay in
dotfiles. On a new machine, build it once:

```powershell
pwsh -NoProfile -File "$env:XDG_CONFIG_HOME/overshell/extensions/taj-agents/Build.ps1"
```

The build requires the .NET 11 SDK and Windows Native AOT C++ build tools, both
available on this machine. Running the resulting executable requires neither.
The helper honours `OVERSHELL_STATE_DIR`, `XDG_STATE_HOME`, then
`%LOCALAPPDATA%/OverShell`, matching OverShell's own path resolution.

It requires **OverShell 0.7.0 or newer**. With the local NuGet feed registered,
close the running OverShell instance and launch `dnx OverShell@0.7.0` to activate
it. Older releases ignore the `process` entry.

Microsoft's [file-based app documentation](https://learn.microsoft.com/en-us/dotnet/core/sdk/file-based-apps)
covers running and publishing these apps. No project file, NuGet dependency, or
reference to either application's DLLs is needed by this publisher.

The general host can also run the source directly, with automatic build caching:

```jsonc
"process": {
  "command": "dotnet",
  "args": ["run", "--file", "{configDir}/extensions/taj-agents/TajAgents.cs",
           "--no-launch-profile", "--verbosity", "quiet", "--disable-build-servers"]
}
```

That form needs no explicit build step, but retains the SDK launcher. The native
command is configured here because of the measured difference below.

## Reading the bar

Each session shows a harness mark followed by its number and status:

- OpenCode uses the same two-tone frame and lower block as OverShell's tabs.
  `GH` is Copilot, `CL` Claude, `CX` Codex. With icons disabled, OpenCode uses `OC`.
- A number identifies a live agent session, independently of tab order.
- Blue `●`: working. Amber `?`: question/permission waiting for you.
- Green `✓`: completed with an unread result. Red `!`: error.
- Grey `○`: idle, when enabled. Grey `…`: state not yet known.
- `+N`: further matching sessions beyond the configured pill limit.

Click a session's icon or status to focus its terminal. Click `AI N` to focus the highest-priority
session; click `+N` to focus the first overflowing session. Questions and errors
take precedence when space is limited. Existing visible sessions keep their slots
across state changes.

Plain shell tabs are excluded. Known session IDs are grouped by harness; without
an ID each agent-bearing terminal is kept separate. The most actionable view wins
when multiple terminals show the same session. Numbers survive state/visibility
changes and are released when the session disappears.

Pending requests remain visible even if a harness reports `Idle`. Unread results
remain visible until OverShell marks them reviewed. Errors follow OverShell's
attention state. These are the main sessions OverShell observes, not nested
subagents inside OpenCode or other harnesses.

## Lifetime and resource use

- One publisher for all monitors, with one persistent IPC connection.
- No HTTP polling, screen scraping, per-update process launches, animation, or
  refresh loop. OverShell coalesces changes on its existing 500 ms heartbeat.
- Only changed bar values are sent. Taj's `announce` signal forces replay after
  its startup/reload. Shubbak reconnects receive a full replay too.
- The OpenCode bitmap is generated once per colour and cached. Taj's existing
  image source decodes it once per changed value; state changes only update text.
- The publisher leases `overshell-agents-online` on its pipe. The `with-agents`
  profile is selected only while that context holds, so a publisher/OverShell
  crash hides old values automatically. Graceful shutdown also clears them.
- If Shubbak is absent, reconnect attempts back off from one to thirty seconds.

Measured on this machine on 2026-11-17, with two static sessions and a private
named-pipe server, after startup, over a 15-second idle sample:

| Launch | Private memory | Working set | CPU time in sample |
|---|---:|---:|---:|
| `dotnet run --file` | 89.5 MiB | 211.3 MiB | 109 ms, in the SDK runner |
| Managed executable | 11.2 MiB | 38.4 MiB | 0 ms measured |
| Native executable (configured) | 5.7 MiB | 18.4 MiB | 0 ms measured |

These are whole publisher process-tree measurements, including the hidden console
host, excluding OverShell/Shubbak themselves. Every variant sent **zero idle IPC
updates**. Zero measured CPU in a short idle sample is not a promise of zero CPU
during state changes, reconnects or startup. Direct `dotnet TajAgents.cs` was also
measured and retained the SDK runner on this installation.

`signalPrefix`, `controlSignal`, `onlineContext`, and `pipeName` can also be
overridden in the extension settings. The first three must match the KDL. Normally
the pipe name is derived from the current user's SID and optional
`SHUBBAK_INSTANCE`.

## Checks and troubleshooting

```powershell
dotnet run --file TajAgents.Tests.cs --no-launch-profile --verbosity quiet
W:\Github\Shubbak\dist\shubbak.exe check-config
```

The tests cover filtering, session deduplication, unread acknowledgement, stable
slots, overflow, Unicode, a real private named pipe, replay, click routing,
reconnect and EOF cleanup. The private pipe does not change the live bar.

An additional real-OverShell probe on a private desktop passed 12 checks, including
report-to-publisher updates, clicking into the correct terminal, hiding a reviewed
result, live `showIdle`, graceful shutdown, and killing the host without leaving a
publisher behind. The generic host's full .NET suite passed 601 tests.

If the zone is missing, confirm the new OverShell build is running and the
extension is enabled. Launch OverShell with `OVERSHELL_TRACE_AGENTS=1` to see
extension launch/stderr diagnostics in `%TEMP%/overshell-agents.log`.
`shubbak contexts` shows whether `overshell-agents-online` is held.
