# Hide Any Window — Claude Code guide

Windows utility that auto-hides windows of chosen apps (from screen, taskbar, and
Alt-Tab), including UIAccess apps like Magnifier. Three parts that share state through
two files:

- `service/` — AutoHotkey v2 script, compiled to a **UIAccess** exe. Watches windows via
  `SetWinEventHook` and hides matches (`WinHide` + `ITaskbarList::DeleteTab`).
- `manager/` — WinUI 3 / .NET 8 desktop app (the GUI). Reads/writes the config.
- `dist/` — `build.ps1` + Inno Setup script that compile, sign, and package the installer.

The two processes communicate ONLY through:
- `%APPDATA%\HideAnyWindow\config.json` — manager writes, service polls its mtime at ~1 Hz.
- Named mutex `HideAnyWindow_Service_Running` — service holds it; manager checks liveness.

## Build / test / run commands

Build the GUI (Debug):

    dotnet build manager/HideAnyWindowManager.sln

Run the C# unit tests (xUnit):

    dotnet test manager/HideAnyWindowManager.sln

Run the AHK service tests — each is a standalone script that pops a MsgBox and exits
0 (pass) / 1 (fail). Run individually with AHK v2:

    & "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" service\test\test_config.ahk
    # also test_log.ahk, test_registry.ahk

YOU MUST dismiss the MsgBox, then check the exit code (0 = pass). The tests are
interactive and currently run against the real `%APPDATA%\HideAnyWindow` files.

Build the full signed installer (compiles the service via Ahk2Exe, generates/reuses a
self-signed cert, signs, publishes the manager, runs Inno Setup):

    powershell -ExecutionPolicy Bypass -File dist\build.ps1
    # Output: dist\HideAnyWindow-Setup.exe

## IMPORTANT gotchas (these will bite you)

- IMPORTANT: The manager exe is `requireAdministrator` + `uiAccess=false` (`app.manifest`).
  The SERVICE exe is the UIAccess binary. The manager LAUNCHES the service via
  ShellExecute (`UseShellExecute=true`) — never CreateProcess. CreateProcess on a
  uiAccess binary fails with `ERROR_ELEVATION_REQUIRED (740)`. The logon Scheduled Task
  therefore targets the MANAGER with `--start-service`, not the service exe.

- IMPORTANT: The C# test project does NOT `ProjectReference` the manager. The manager
  targets `net8.0-windows` + `UseWinUI`, which crashes the test host on bootstrap.
  Tests `<Compile Include>` the Models/Services/Util/ViewModels source files directly into
  a plain `net8.0` assembly (`IconHelper.cs` is excluded because it pulls in WinUI). When
  you add a testable type, put it in Models/Services/Util/ViewModels so the link-glob
  picks it up — and keep it free of WinUI (`Microsoft.UI.*`) references.

- `dist\build.ps1` hard-codes tool paths and will `throw` if any is missing:
  Ahk2Exe `C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe`,
  base `C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe`,
  `signtool.exe` (Windows 10/11 SDK), Inno Setup `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`.

- `build.ps1` does two non-obvious binary fix-ups — do NOT remove them:
  1. Auto-clicks the benign "Ahk2Exe Warning" dialog (Ahk2Exe heuristic vs. the v2 base file).
  2. Zeroes the PE Certificate-Table directory entry inherited from the AHK base file,
     otherwise signtool fails `0x800700C1` ("bad EXE format").
  It also copies `*.xbf` + `HideAnyWindowManager.pri` from `bin\Release` into the publish
  output — WinAppSDK 2.0 unpackaged publish drops them, and the manager crashes
  (`0xc000027b`) without them.

- SECURITY: The installer adds the self-signed cert (`CN=HideAnyWindowDev`, pfx password
  `devpassword`) to the machine **Trusted Root + TrustedPublisher** stores via certutil so
  the UIAccess service can elevate silently; uninstall removes it. Never ship a public
  release signed with this throwaway dev cert. (A scoped-trust improvement is recommended —
  see `docs/AUDIT-2026-05.md`.)

- AHK v2 source quirks — don't "fix" these, they are deliberate:
  `#Warn All, Off` in `main.ahk` silences false-positive "LocalSameAsGlobal" warnings on
  legitimate cross-file calls; `config.ahk`/`registry.ahk` INLINE the
  `A_AppData\HideAnyWindow\...` path rather than routing through a helper for the same reason.

- The service refuses to hide `hideanywindowmanager.exe` (hard-coded denylist in `main.ahk`).

- IMPORTANT: `serviceState: "stopped"` means the service process **must not exist** — it is not a
  paused state. The manager's Stop button only writes `stopped` to config.json; the service sees
  it on its next 1 Hz poll, restores every hidden window, releases the mutex and `ExitApp`s. The
  service also exits immediately if it starts up while `stopped`, and the `--start-service` logon
  path skips the launch entirely (`ServiceController.ShouldStartAtLogon`). Do not reintroduce a
  resident paused mode — a service idling in Task Manager after "Stop" is what issue #1 was.

- The service sets `#NoTrayIcon`. AutoHotkey's default tray menu ("Suspend Hotkeys" / "Pause
  Script") falsely implies the service owns global hotkeys. It registers **no hotkeys at all**.

## State & log files (all under `%APPDATA%\HideAnyWindow\`)

- `config.json` — camelCase JSON (`schemaVersion` / `serviceState` / `rules`), written
  atomically (temp + move) on both sides.
- `hidden.json` — crash-recovery list of currently-hidden windows + their original ex-styles.
- `service.log` — service activity; **hide failures are logged here as `WARN` lines**
  (there is no separate `hide-failures.log` despite the `.gitignore` entry).
- `manager.log` — manager activity.

## Conventions

- C#: `Nullable` + `ImplicitUsings` enabled, file-scoped namespaces. JSON is camelCase.
- Manager builds **x64 only** (the solution maps `Any CPU` -> `x64`); the installer is x64-only.
- Branch off `main` and open a PR — do not push straight to `main`.
- Skills with deeper, on-demand context live in `.claude/skills/` (`build-installer`,
  `ahk-service`). Load them when working on packaging or the service.
