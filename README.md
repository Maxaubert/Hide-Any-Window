<div align="center">
  <img src="dist/icon.png" alt="Hide Any Window" width="128">

  # Hide Any Window

  Auto-hide any Windows app, even Magnifier. No taskbar icon. No Alt-Tab entry. No fuss.

  [![Latest release](https://img.shields.io/github/v/release/Maxaubert/Hide-Any-Window?style=flat-square)](https://github.com/Maxaubert/Hide-Any-Window/releases/latest)
  [![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=flat-square)](https://github.com/Maxaubert/Hide-Any-Window/releases/latest)
</div>

---

<table align="center">
  <tr>
    <td align="center"><img src="docs/screenshots/Main.png" alt="" width="420"></td>
    <td align="center"><img src="docs/screenshots/AddProcess.png" alt="" width="420"></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><img src="docs/screenshots/StartStopService.png" alt="" width="420"></td>
  </tr>
</table>

## What it does

Pick an app. Toggle "hide" on. From then on, every time a window of that app appears it vanishes the moment it shows: gone from the screen, gone from the taskbar, gone from Alt-Tab. Toggle off and the window comes back.

Works on apps that resist normal "minimize to tray" tools, including Windows Magnifier.

## Install

1. Download HideAnyWindow-Setup.exe below.
2. Run the installer
3. (Optional) Run service on startup
4. Done.

> You may need to unblock the installer the first time. It is not signed by a trusted publisher, so SmartScreen and some antivirus tools flag it as unknown. Right-click the file > Properties > tick **Unblock** at the bottom, or click **More info** > **Run anyway** when SmartScreen appears.

## Use

1. Open **Hide Any Window** from the Start menu.
2. Click **Start service** in the footer.
3. Click **+ Add**, pick the app you want to hide, click **Add**.
4. Toggle the row on.

Open the app and it disappears. Toggle off when you want it back.

## Settings

The gear icon in the toolbar opens **Settings**. One option for now:

- **Start at logon**: when on, the service auto-launches when you sign in to Windows. Off by default.

## Uninstall

Settings > Apps > Hide Any Window > Uninstall. Removes the manager, the service, the trusted certificate, and the optional logon task.

## Build from source

For developers.

Requirements:

- Windows 10 or 11
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [AutoHotkey v2](https://www.autohotkey.com/) (only needed to build the service exe)
- [Inno Setup 6](https://jrsoftware.org/isdl.php) (only needed to build the installer)
- Windows 10/11 SDK, for `signtool.exe` (only needed to sign the build)

```powershell
git clone https://github.com/Maxaubert/Hide-Any-Window.git
cd Hide-Any-Window
dotnet build manager\HideAnyWindowManager.sln
```

To produce the installer:

```powershell
powershell -ExecutionPolicy Bypass -File dist\build.ps1
```

Output: `dist\HideAnyWindow-Setup.exe`.

## How it works

Two pieces, one shared config file.

- **Service** (`service/`): a compiled AutoHotkey v2 script with a UIAccess manifest. Watches for windows of configured apps via `SetWinEventHook`, hides matches with `WinHide` plus `ITaskbarList::DeleteTab`. Holds a named mutex so the manager can detect liveness.
- **Manager** (`manager/`): a WinUI 3 / .NET 8 desktop app. Reads and writes `%APPDATA%\HideAnyWindow\config.json`. Talks to the service through that file plus the named mutex.

## Security note

To hide windows of elevated and UIAccess apps (like Magnifier), the service runs with
UIAccess and elevated privilege. To make that work without a UAC prompt on every logon:

- The installer installs a **self-signed code-signing certificate** (`CN=HideAnyWindowDev`)
  into your machine's certificate stores and removes it on uninstall. This lets Windows
  treat the bundled service binary as trusted so it can elevate silently.
- When **Start at logon** is enabled, a scheduled task launches the manager with the
  highest privileges at sign-in.

If you build from source, the cert is a throwaway dev certificate — do not redistribute a
build signed with it. Because official releases are not signed by a recognised publisher,
SmartScreen and some antivirus tools will flag the installer as unknown the first time.

## Troubleshooting

The service and manager write plain-text logs to `%APPDATA%\HideAnyWindow\`:

- `service.log` — service activity. A window that won't hide is logged here as a `WARN`
  line (usually the target is more elevated than the service can reach).
- `manager.log` — manager activity (config saves, service start/stop).

If a window stays hidden after you toggle a rule off or close the app, restart the service
from the footer — on the next start it restores any windows still recorded in `hidden.json`.

## License

MIT — see [LICENSE](LICENSE).
