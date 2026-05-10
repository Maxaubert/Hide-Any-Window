# Hide Any Window — Phase B Design

## Goal

Replace Phase A's hotkey-driven, single-script tool with a two-process auto-hide system:

1. A **WinUI 3 manager app** that lets the user configure which apps should be auto-hidden (add via a Cheat Engine-style process picker, toggle individual rules, stop/start the service).
2. A **background AHK service** that watches the user's session and automatically hides any window belonging to a configured app — using event-driven hooks (no polling) so the performance footprint is effectively zero.

The two processes are loosely coupled: they share a single JSON config file, and the manager detects whether the service is running via a named mutex.

## Architecture

Two cooperating processes plus a shared config file. No named pipes, no sockets, no message bus.

```
┌──────────────────────────┐         ┌──────────────────────────┐
│  Manager (WinUI 3, .NET) │         │  Service (AHK v2)        │
│  - runs un-elevated      │         │  - runs elevated         │
│  - on-demand UI          │         │  - background, no UI     │
│  - reads/writes config   │         │  - reads config          │
│  - launches service      │ ◀─────▶ │  - SetWinEventHook       │
│    (UAC prompt)          │  config │  - hides matching windows│
│  - watches mutex for     │  .json  │  - holds named mutex     │
│    service liveness      │         │  - restores on stop/exit │
└──────────────────────────┘         └──────────────────────────┘
              │                                     │
              ▼                                     ▼
   %APPDATA%\HideAnyWindow\config.json (shared, atomic writes)
   %APPDATA%\HideAnyWindow\hidden.json (service-only, crash recovery)
   Mutex: HideAnyWindow_Service_Running (manager polls, service holds)
```

### Why two processes (not one)

- The hide logic must run elevated to handle UIAccess windows like Magnifier (Phase A established this).
- A WinUI 3 manager would need to be elevated too if combined — meaning a UAC prompt every time the user opens it. Splitting keeps the manager friction-free.
- Each piece can crash, restart, or be updated independently without breaking the other.

### Why JSON + mutex (not IPC)

- Config changes are infrequent and small. File watch (`ReadDirectoryChangesW`) is a perfectly fast notification mechanism with zero polling.
- Liveness check via mutex is a single Win32 call that takes microseconds. No background socket or pipe to maintain.
- Both processes can recover from each other's crashes by re-reading the file or re-acquiring the mutex.

## Components

### Service (AHK)

| Component | Responsibility |
|---|---|
| **Startup scan** | On launch, enumerate top-level windows once. Hide any whose owning process matches an enabled rule. Catches windows that already existed before service started. |
| **Window event hook** | `SetWinEventHook(EVENT_OBJECT_SHOW)` — Windows calls our callback when any window is shown. Callback resolves window's owning process, checks rules, hides if matched. Zero polling. |
| **Config watcher** | `ReadDirectoryChangesW` on `%APPDATA%\HideAnyWindow\`. On change to `config.json`: re-read, restore windows belonging to disabled/removed rules, hide any new matches, update `serviceState`. |
| **Hidden-window registry** | Same `{hwnd, originalExStyle}` records as Phase A, but augmented with `ruleId` so we know which rule owns each hidden window. Persisted to `hidden.json` on every change. |
| **Status mutex** | Owns a named mutex `HideAnyWindow_Service_Running` for the lifetime of the process. |
| **Stop handling** | When config flips to `serviceState: "stopped"`: restore every window in the registry, clear the registry, write empty `hidden.json`, no-op the event-hook callback until state flips back. The process keeps running (mutex held, hooks registered, watching config for the resume signal). |
| **Graceful shutdown** | On `WM_CLOSE` or `OnExit`: restore all hidden windows, release the mutex, exit. |
| **Crash recovery** | On startup, read `hidden.json`; restore any windows recorded there before doing anything else. Prevents orphan hidden windows from a previous crash. |
| **Logging** | Append failures (hide-failure, malformed config, etc.) to `service.log` in `%APPDATA%\HideAnyWindow\`. |

### Manager (WinUI 3)

| Component | Responsibility |
|---|---|
| **Main window** | Approved mockup — rule list with row-level toggle, Add/Remove toolbar, footer with service status + Stop/Start. |
| **Add picker (modal)** | Approved mockup — enumerate visible top-level windows, dedupe by exe, show as searchable list. Pick one → row added to rules with `enabled: true` by default. |
| **Config I/O** | Read `config.json` on open; debounced write on toggle/add/remove (200ms after last change). Atomic write via `config.json.tmp` + rename. |
| **Service launcher** | "Start service" launches `hide-any-window-service.exe` (the compiled AHK script) using `Process.Start` with `Verb = "runas"` — triggers the UAC prompt, service runs elevated. |
| **Service stopper** | "Stop service" writes `serviceState: "stopped"` to config. Service detects, restores everything, holds. (Manager does NOT try to kill the elevated service process — it can't from un-elevated context.) |
| **Liveness watch** | Once per second: `OpenMutex("HideAnyWindow_Service_Running")` — if the handle is non-null, service is running; close immediately. Updates the footer dot/text. Microseconds per call. |
| **Config validation** | If `config.json` is malformed (parse fails, schema mismatch), show a dialog: "Config file is corrupted. Open in Notepad to fix, or click Reset to start fresh." |

### Shared files

**`%APPDATA%\HideAnyWindow\config.json`** — the single source of truth for what to hide and whether the service should be active. Written by manager; read by both.

**`%APPDATA%\HideAnyWindow\hidden.json`** — service-only crash-recovery cache. Mirror of the in-memory hidden-window registry.

**`%APPDATA%\HideAnyWindow\service.log`** — append-only log of service errors and notable events.

## Config schema

```json
{
  "schemaVersion": 1,
  "serviceState": "running",
  "rules": [
    {
      "id": "magnify-exe",
      "exe": "magnify.exe",
      "name": "Magnifier",
      "enabled": true
    },
    {
      "id": "discord-exe",
      "exe": "Discord.exe",
      "name": "Discord",
      "enabled": false
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | int | Bump on breaking changes. Service refuses unknown versions. |
| `serviceState` | `"running"` \| `"stopped"` | The Stop/Start button's only effect. Default `"running"`. |
| `rules[].id` | string | Stable identifier. Generated as lowercase exe with `.` replaced by `-` (e.g., `magnify-exe`). Used to match hidden windows back to their rule across config edits. |
| `rules[].exe` | string | Match key. Compared case-insensitively to the basename of the owning process's executable path. Phase B matches by exe only. |
| `rules[].name` | string | Friendly display name. Auto-populated on add from the executable's `FileVersionInfo.FileDescription` (or basename if absent). User-editable in a future phase. |
| `rules[].enabled` | bool | Row toggle. `false` = rule exists but service ignores it. |

### `hidden.json` schema (service-only)

```json
{
  "entries": [
    { "hwnd": 12345678, "exStyle": 256, "ruleId": "magnify-exe", "title": "Magnifier" }
  ]
}
```

## Data flow

**User adds Magnifier:**

1. User clicks **+ Add** → manager opens picker, calls `EnumWindows`, dedupes by owning process, shows the list.
2. User picks Magnifier → manager appends to `rules` with `enabled: true`, writes `config.json` atomically.
3. Service's `ReadDirectoryChangesW` callback fires → service re-reads config → finds new enabled rule for `magnify.exe` → enumerates current windows for that exe → hides them.

**User toggles Magnifier off:**

1. Toggle switch flips → manager updates `rules[i].enabled = false`, writes config.
2. Service detects change → finds windows in registry with `ruleId: "magnify-exe"` → restores their styles, calls `WinShow` → removes them from registry → updates `hidden.json`.

**User clicks "Stop service":**

1. Manager sets `serviceState: "stopped"`, writes config.
2. Service detects → iterates entire registry → restores everything → clears registry + `hidden.json` → flips internal "paused" flag.
3. Event-hook callback continues firing but immediately returns when paused.
4. Mutex stays held (process is alive). The footer flips to "Service stopped" because the manager treats `serviceState == "stopped"` as the user-visible "stopped" state — see footer-display rule below.

**User clicks "Start service" while service is running but paused:**

1. Manager sets `serviceState: "running"`.
2. Service detects → un-pauses → runs the startup scan → hides matches.
3. Manager footer flips to "Service running" on next read of `config.json`.

**User clicks "Start service" while service process isn't running:**

1. Manager checks mutex → not present → launches `hide-any-window-service.exe` with `Verb = runas`. (Manager also pre-writes `serviceState: "running"` so the freshly-spawned service starts un-paused.)
2. UAC prompt → user approves → service starts elevated → acquires mutex → reads config → runs startup scan.
3. Manager's once-per-second mutex check picks up the new mutex → footer updates to "Service running".

### Footer-display rule

The footer's "running"/"stopped" indicator is a function of two inputs:

| Mutex held? | `serviceState` in config | Footer shows | Button shows |
|---|---|---|---|
| no | (any) | "Service stopped" | "Start service" |
| yes | `"stopped"` | "Service stopped" | "Start service" |
| yes | `"running"` | "Service running" | "Stop service" |

This collapses the system's three internal states (process gone / paused / active) into two user-visible states ("stopped" / "running"), which matches what the user actually cares about: is anything being hidden right now?

**Service crash (or kill via Task Manager):**

1. Process dies → mutex auto-released by the OS.
2. Hidden windows stay hidden — they're real windows with `WS_EX_TOOLWINDOW` set; nothing automatic restores them.
3. Manager's liveness check notices missing mutex → footer flips to "Service stopped".
4. User clicks "Start service" → UAC → service starts → reads `hidden.json` first → restores the orphan windows → then starts normal operation (which may re-hide them if their rules are still enabled).

## Error handling

| Scenario | Behavior |
|---|---|
| Service can't hide a window (Phase A's UIAccess case for non-Magnifier UIAccess apps) | Append to `service.log`. Do not register in hidden-window registry. No tooltip — there's no user attending the service. Manager could surface this via a "Show log" link in v3. |
| `config.json` malformed mid-edit | Service ignores until next valid write (JSON parse failure → log + skip). Manager refuses to load → modal dialog: "Config file is corrupted. [Open in Notepad] [Reset to default]". |
| `config.json` missing | Service treats as empty `rules` and `serviceState: "running"`. Manager creates a fresh one on first save. |
| `hidden.json` malformed | Service logs and treats as empty. Worst case: orphan hidden windows remain hidden until the user manually finds them. |
| Both processes write `config.json` at the same instant | Atomic write (`tmp` + rename) ensures one wins cleanly; the other's notification picks up the winning version. Race is benign because manager is the only writer in steady state. |
| Service started while another instance is already running | `CreateMutex` returns an existing handle → second instance exits immediately without touching anything. Standard `#SingleInstance Force` semantics. |
| Manager started while another instance is already running | WinUI 3 single-instance pattern (named pipe activation or `Mutex` check at `App.OnLaunched`) → second instance brings the existing window forward and exits. |
| Manager closes while service is running | Service unaffected. Reopening the manager re-reads current config and reflects current state. |

## Testing plan

Manual, mirroring Phase A's approach — this is real-OS window manipulation; meaningful unit tests would test mocks of mocks.

| # | Scenario | Expected |
|---|---|---|
| 1 | Service starts with no `config.json` | Service idles, no windows hidden, no errors logged. Manager footer shows "Service running" within 1s. |
| 2 | Add Magnifier via picker, Magnifier already running | Magnifier window vanishes within ~200ms of click. |
| 3 | Open Magnifier while rule is enabled | New Magnifier window vanishes immediately on appearance (event hook fires). |
| 4 | Toggle Magnifier rule off | Magnifier window reappears, stays visible until toggled back on. |
| 5 | Click "Stop service" | All hidden windows reappear. Footer flips to "Service stopped". Adding new rules has no effect until restart. |
| 6 | Click "Start service" while paused | All previously-matching visible windows re-hide. Footer flips to "Service running". |
| 7 | Kill service via Task Manager while a window is hidden | Footer flips to "Service stopped" within 1s. Hidden window stays hidden. Click "Start service" → UAC → window is restored from `hidden.json` then re-hidden by current rules. |
| 8 | Edit `config.json` in Notepad while service runs | Service picks up the change without restart (file watcher fires). |
| 9 | Add an app that's already in the rules list via picker | Picker shows "already monitored" annotation. The Add button is disabled while such a row is selected. |
| 10 | Run two manager instances | Second instance brings first window forward and exits. |

## Out of scope for Phase B

- **Window-title matching** — rules are exe-only. A future phase can add an optional `titlePattern` field.
- **Auto-start at logon** — user must manually place `hide-any-window-service.exe` in `shell:startup` (or set up a Task Scheduler task themselves). The README will document the steps. A future phase can add a "Start at logon" checkbox in the manager.
- **Service tray icon** — manager footer is the only status surface. No tray clutter.
- **Per-rule "currently hidden" indicator** — manager shows configured rules, not live runtime state of windows.
- **Editing rule name after add** — `name` field exists in schema but the manager has no edit affordance in v2.
- **Hotkeys** — explicitly removed.
- **Multi-window selection in picker** — single-pick only.
- **Surfacing service-log errors in the manager UI** — log file is written; no UI to view it (open in Notepad if needed).

## Appendix: file/process inventory

| Path / artifact | Owner | Contents |
|---|---|---|
| `%APPDATA%\HideAnyWindow\config.json` | manager (writer) / service (reader) | Rules + service state |
| `%APPDATA%\HideAnyWindow\hidden.json` | service only | Crash-recovery snapshot of hidden windows |
| `%APPDATA%\HideAnyWindow\service.log` | service only | Errors and notable events |
| Mutex `HideAnyWindow_Service_Running` | service holds; manager queries | Liveness signal |
| `hide-any-window-service.exe` | (new build artifact) | Compiled AHK service binary |
| `HideAnyWindowManager.exe` | (new build artifact) | WinUI 3 manager binary |
