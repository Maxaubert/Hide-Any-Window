# Hide Any Window — Phase B Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a WinUI 3 / .NET 8 manager app that lets the user add/remove auto-hide rules via a process picker (Cheat-Engine-style — visible windows only), toggle each rule on/off, and stop/start the running service. Reads/writes the same `%APPDATA%\HideAnyWindow\config.json` that the AHK service watches; detects the service via the named mutex `HideAnyWindow_Service_Running`.

**Architecture:** Single unpackaged WinUI 3 desktop app. Lightweight MVVM (no framework — manual `INotifyPropertyChanged`). One `MainWindow` plus one `ContentDialog` for the Add picker. Three service classes (`ConfigStore`, `ServiceController`, `ProcessEnumerator`) instantiated once in `App.xaml.cs` and passed to the window. The manager NEVER runs elevated — the service does the privileged work; the manager only edits the shared JSON file and queries the named mutex.

**Tech Stack:** .NET 8 SDK, Windows App SDK 1.5+, WinUI 3 (XAML), C# 12, `System.Text.Json`, `System.Threading.Mutex`, Win32 P/Invoke (`EnumWindows`, `GetWindowThreadProcessId`, `IsWindowVisible`, `QueryFullProcessImageName`).

**Note on testing:** Pure logic (config I/O, mutex check, process enumeration) gets xUnit tests in a separate test project. UI (XAML rendering, button clicks, dialog flow) is verified manually with explicit pass/fail steps — there is no fast, reliable WinUI 3 UI test framework that's worth the setup for a project this size.

---

## Prerequisites

Before starting Task 1:

- [ ] **.NET 8 SDK installed.** Run `dotnet --version`. Expect `8.x.xxx`. If not installed, download from https://dotnet.microsoft.com/download/dotnet/8.0 (the SDK installer, not the runtime).

- [ ] **WinUI 3 project templates installed.** Run once: `dotnet new install Microsoft.WindowsAppSDK.ProjectTemplates`. Expected: lists templates including `winui` / `WinUI 3 Blank App`.

- [ ] **AHK v2 still installed** with `AutoHotkey64_UIA.exe` at `C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe`. (Used by the manager's "Start service" button.)

---

## File Structure

All new code lives under a new top-level `manager/` directory. Two projects: the WinUI 3 app and a separate xUnit test project.

```
manager/
  HideAnyWindowManager.sln                 solution file
  src/HideAnyWindowManager/
    HideAnyWindowManager.csproj            unpackaged WinUI 3 app
    App.xaml + App.xaml.cs                 entry point, service composition
    MainWindow.xaml + MainWindow.xaml.cs   the rule list + toolbar + footer
    AddPickerDialog.xaml + .xaml.cs        the "Add app to monitor" modal
    Models/
      Config.cs                            POCO for the JSON root
      Rule.cs                              POCO for one rule entry
      WindowedProcessInfo.cs               row in the picker
    Services/
      ConfigStore.cs                       atomic JSON I/O, debounced save
      ServiceController.cs                 mutex check + launch the AHK service
      ProcessEnumerator.cs                 P/Invoke EnumWindows for the picker
    ViewModels/
      MainViewModel.cs                     observable state for MainWindow
      RuleViewModel.cs                     observable wrapper around a Rule
    Util/
      ObservableObject.cs                  minimal INotifyPropertyChanged base
      Win32.cs                             P/Invoke declarations
  test/HideAnyWindowManager.Tests/
    HideAnyWindowManager.Tests.csproj      xUnit test project
    ConfigStoreTests.cs
    ServiceControllerTests.cs
README.md                                  (modify — point at the manager)
```

---

## Task 1: Bootstrap the WinUI 3 project (unpackaged)

**Files:**
- Create: `manager/HideAnyWindowManager.sln`
- Create: `manager/src/HideAnyWindowManager/HideAnyWindowManager.csproj`
- Create: `manager/src/HideAnyWindowManager/App.xaml`, `App.xaml.cs`
- Create: `manager/src/HideAnyWindowManager/MainWindow.xaml`, `MainWindow.xaml.cs`

- [ ] **Step 1: Generate a WinUI 3 blank app from the template**

From the repo root, run:

```powershell
cd manager
mkdir src
cd src
dotnet new winui --name HideAnyWindowManager
```

Expected output: "The template 'WinUI 3 Blank App, Packaged (WinUI 3 in Desktop)' was created successfully." A `HideAnyWindowManager` directory appears containing `.csproj`, `App.xaml`, `MainWindow.xaml`, and a `Package.appxmanifest`.

- [ ] **Step 2: Convert it to unpackaged (single .exe, no MSIX)**

Edit `manager/src/HideAnyWindowManager/HideAnyWindowManager.csproj`. Inside the first `<PropertyGroup>`:

- Add: `<WindowsPackageType>None</WindowsPackageType>`
- Remove (or set to `false`): `<EnableMsixTooling>true</EnableMsixTooling>`

Then delete the now-unused MSIX manifest and entry-point glue:

```powershell
Remove-Item Package.appxmanifest, app.manifest -ErrorAction SilentlyContinue
```

(If there's an `Assets/` folder with default WinUI placeholder images, leave it — those are referenced by App.xaml.)

In `HideAnyWindowManager.csproj`, also remove the `<ItemGroup>` lines that reference `Package.appxmanifest` if any remain.

- [ ] **Step 3: Create the solution file**

```powershell
cd ..\..   # back to manager/
dotnet new sln --name HideAnyWindowManager
dotnet sln add src\HideAnyWindowManager\HideAnyWindowManager.csproj
```

Expected: `manager/HideAnyWindowManager.sln` exists; `dotnet sln list` shows the project.

- [ ] **Step 4: Build and run to verify**

```powershell
dotnet build manager\HideAnyWindowManager.sln
```

Expected: `Build succeeded`. Then:

```powershell
dotnet run --project manager\src\HideAnyWindowManager
```

Expected: a small blank window titled "HideAnyWindowManager" with a single button labeled "Click me" (the WinUI 3 template's default content). Close it.

If the build fails complaining about `WindowsPackageType` or about a missing `Microsoft.WindowsAppSDK` runtime, ensure the latest Windows App SDK is referenced (the template should pull it as a NuGet package; if needed, run `dotnet add package Microsoft.WindowsAppSDK` inside the project directory).

- [ ] **Step 5: Add `.gitignore` entries for build output**

Append to the repo root `.gitignore`:

```gitignore

# .NET / WinUI 3 build outputs
manager/**/bin/
manager/**/obj/
manager/**/AppPackages/
manager/**/BundleArtifacts/
manager/**/Generated Files/
manager/.vs/
```

- [ ] **Step 6: Commit**

```powershell
git add manager .gitignore
git commit -m "scaffold(manager): unpackaged WinUI 3 blank app via dotnet new winui"
```

---

## Task 2: Models — `Rule`, `Config`, `WindowedProcessInfo`

**Files:**
- Create: `manager/src/HideAnyWindowManager/Models/Rule.cs`
- Create: `manager/src/HideAnyWindowManager/Models/Config.cs`
- Create: `manager/src/HideAnyWindowManager/Models/WindowedProcessInfo.cs`

- [ ] **Step 1: `Rule.cs`**

```csharp
namespace HideAnyWindowManager.Models;

public sealed class Rule
{
    public string Id { get; set; } = "";
    public string Exe { get; set; } = "";
    public string Name { get; set; } = "";
    public bool Enabled { get; set; } = true;

    /// <summary>Generates a stable id from an exe name, e.g. "magnify.exe" -&gt; "magnify-exe".</summary>
    public static string IdFromExe(string exe)
        => exe.ToLowerInvariant().Replace('.', '-');
}
```

- [ ] **Step 2: `Config.cs`**

```csharp
using System.Collections.Generic;

namespace HideAnyWindowManager.Models;

public sealed class Config
{
    public int SchemaVersion { get; set; } = 1;
    public string ServiceState { get; set; } = "running";
    public List<Rule> Rules { get; set; } = new();
}
```

- [ ] **Step 3: `WindowedProcessInfo.cs`**

```csharp
namespace HideAnyWindowManager.Models;

/// <summary>One row in the Add picker — a process that has at least one visible top-level window.</summary>
public sealed class WindowedProcessInfo
{
    public string Exe { get; set; } = "";        // basename, e.g. "magnify.exe"
    public string Name { get; set; } = "";       // friendly name, e.g. "Magnifier"
    public string FullPath { get; set; } = "";   // for tooltip / debugging
    public bool AlreadyMonitored { get; set; }   // true if Exe is already in current Config.Rules
}
```

- [ ] **Step 4: Commit**

```powershell
git add manager\src\HideAnyWindowManager\Models
git commit -m "feat(manager): POCO models for Rule, Config, WindowedProcessInfo"
```

---

## Task 3: `ConfigStore` — atomic JSON I/O with debounced save

**Files:**
- Create: `manager/src/HideAnyWindowManager/Services/ConfigStore.cs`
- Create: `manager/test/HideAnyWindowManager.Tests/HideAnyWindowManager.Tests.csproj`
- Create: `manager/test/HideAnyWindowManager.Tests/ConfigStoreTests.cs`

The store reads and writes the same JSON the AHK service watches. Writes are atomic (`tmp + rename`) and debounced (200ms after last call) so rapid toggles don't spam the disk.

- [ ] **Step 1: Create the test project**

```powershell
cd manager\test
dotnet new xunit --name HideAnyWindowManager.Tests
cd HideAnyWindowManager.Tests
dotnet add reference ..\..\src\HideAnyWindowManager\HideAnyWindowManager.csproj
cd ..\..
dotnet sln add test\HideAnyWindowManager.Tests\HideAnyWindowManager.Tests.csproj
```

Note: the test project targets `net8.0` by default; that's fine — it doesn't need WinUI.

- [ ] **Step 2: Write the failing test**

`manager/test/HideAnyWindowManager.Tests/ConfigStoreTests.cs`:

```csharp
using System.IO;
using System.Threading.Tasks;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Services;
using Xunit;

public class ConfigStoreTests
{
    [Fact]
    public async Task RoundTripsConfigToDisk()
    {
        var path = Path.Combine(Path.GetTempPath(), $"haw-test-{System.Guid.NewGuid():N}.json");
        var store = new ConfigStore(path);

        var cfg = new Config
        {
            ServiceState = "stopped",
            Rules = { new Rule { Id = "magnify-exe", Exe = "magnify.exe", Name = "Magnifier", Enabled = true } }
        };
        await store.SaveImmediateAsync(cfg);

        var loaded = await store.LoadAsync();
        Assert.Equal("stopped", loaded.ServiceState);
        Assert.Single(loaded.Rules);
        Assert.Equal("magnify.exe", loaded.Rules[0].Exe);
        Assert.True(loaded.Rules[0].Enabled);

        File.Delete(path);
    }

    [Fact]
    public async Task ReturnsDefaultsWhenFileMissing()
    {
        var path = Path.Combine(Path.GetTempPath(), $"haw-missing-{System.Guid.NewGuid():N}.json");
        var store = new ConfigStore(path);

        var loaded = await store.LoadAsync();
        Assert.Equal("running", loaded.ServiceState);
        Assert.Empty(loaded.Rules);
    }
}
```

- [ ] **Step 3: Run the test — confirm it fails**

```powershell
dotnet test manager\HideAnyWindowManager.sln
```

Expected: build error / "Cannot resolve symbol 'ConfigStore'". That's the failing state.

- [ ] **Step 4: Implement `ConfigStore`**

`manager/src/HideAnyWindowManager/Services/ConfigStore.cs`:

```csharp
using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using HideAnyWindowManager.Models;

namespace HideAnyWindowManager.Services;

public sealed class ConfigStore
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    private readonly string _path;
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private CancellationTokenSource? _debounceCts;

    public string ConfigPath => _path;

    public ConfigStore() : this(DefaultPath()) { }
    public ConfigStore(string path) { _path = path; }

    public static string DefaultPath()
        => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                        "HideAnyWindow", "config.json");

    public async Task<Config> LoadAsync()
    {
        if (!File.Exists(_path))
            return new Config();
        try
        {
            await using var fs = File.OpenRead(_path);
            var cfg = await JsonSerializer.DeserializeAsync<Config>(fs, JsonOpts);
            return cfg ?? new Config();
        }
        catch (JsonException)
        {
            return new Config();   // malformed -> caller can decide whether to overwrite
        }
    }

    /// <summary>Schedules a save for 200ms after the last call. Subsequent calls cancel the prior schedule.</summary>
    public void ScheduleSave(Config cfg)
    {
        _debounceCts?.Cancel();
        _debounceCts = new CancellationTokenSource();
        var token = _debounceCts.Token;
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(200, token);
                await SaveImmediateAsync(cfg);
            }
            catch (TaskCanceledException) { /* superseded */ }
        });
    }

    public async Task SaveImmediateAsync(Config cfg)
    {
        await _writeLock.WaitAsync();
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var tmp = _path + ".tmp";
            await using (var fs = File.Create(tmp))
                await JsonSerializer.SerializeAsync(fs, cfg, JsonOpts);
            // File.Move with overwrite=true is atomic on the same volume.
            File.Move(tmp, _path, overwrite: true);
        }
        finally
        {
            _writeLock.Release();
        }
    }
}
```

- [ ] **Step 5: Run the tests — confirm they pass**

```powershell
dotnet test manager\HideAnyWindowManager.sln
```

Expected: `Passed!  - Failed: 0, Passed: 2`.

- [ ] **Step 6: Commit**

```powershell
git add manager
git commit -m "feat(manager): ConfigStore with atomic write + debounced save + xunit tests"
```

---

## Task 4: `ServiceController` — mutex liveness check + service launcher

**Files:**
- Create: `manager/src/HideAnyWindowManager/Services/ServiceController.cs`
- Create: `manager/test/HideAnyWindowManager.Tests/ServiceControllerTests.cs`

- [ ] **Step 1: Write the failing test**

`ServiceControllerTests.cs`:

```csharp
using System.Threading;
using HideAnyWindowManager.Services;
using Xunit;

public class ServiceControllerTests
{
    [Fact]
    public void DetectsHeldMutex()
    {
        var ctrl = new ServiceController();
        Assert.False(ctrl.IsServiceRunning());   // none held yet

        using var owned = new Mutex(initiallyOwned: false, name: "HideAnyWindow_Service_Running");
        Assert.True(ctrl.IsServiceRunning());
    }
}
```

- [ ] **Step 2: Run — confirm it fails**

```powershell
dotnet test manager\HideAnyWindowManager.sln
```

Expected: "Cannot resolve symbol 'ServiceController'".

- [ ] **Step 3: Implement `ServiceController`**

`manager/src/HideAnyWindowManager/Services/ServiceController.cs`:

```csharp
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace HideAnyWindowManager.Services;

public sealed class ServiceController
{
    private const string MutexName = "HideAnyWindow_Service_Running";

    /// <summary>Returns true if the AHK service process is currently holding its named mutex.</summary>
    public bool IsServiceRunning()
    {
        try
        {
            using var existing = Mutex.OpenExisting(MutexName);
            return true;
        }
        catch (WaitHandleCannotBeOpenedException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            // Mutex exists but we can't open it — treat as running.
            return true;
        }
    }

    /// <summary>Launches the AHK service via AutoHotkey64_UIA.exe. The UIA-signed AHK
    /// auto-elevates without a UAC prompt and gives the script UIAccess privileges.</summary>
    /// <returns>true if launch was attempted; false if the AHK install or script wasn't found.</returns>
    public bool TryStartService(string? scriptPath = null, string? ahkUiaPath = null)
    {
        scriptPath ??= DefaultScriptPath();
        ahkUiaPath ??= DefaultAhkUiaPath();

        if (!File.Exists(scriptPath) || !File.Exists(ahkUiaPath))
            return false;

        var psi = new ProcessStartInfo
        {
            FileName = ahkUiaPath,
            Arguments = "\"" + scriptPath + "\"",
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        Process.Start(psi);
        return true;
    }

    public static string DefaultAhkUiaPath()
        => @"C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe";

    public static string DefaultScriptPath()
    {
        // Resolve relative to the manager's executable: ../../service/main.ahk
        // (In dev the layout is repo/manager/src/HideAnyWindowManager/bin/.../HideAnyWindowManager.exe
        //  with the service at repo/service/main.ahk. The user can override via the optional
        //  parameter to TryStartService when this default is wrong.)
        var exeDir = AppContext.BaseDirectory;
        var probe = Path.GetFullPath(Path.Combine(exeDir, @"..\..\..\..\..\..\service\main.ahk"));
        if (File.Exists(probe))
            return probe;
        // Fallback to a sibling layout (manager and service folders next to each other in deployed build).
        return Path.GetFullPath(Path.Combine(exeDir, @"..\service\main.ahk"));
    }
}
```

- [ ] **Step 4: Run — confirm tests pass**

```powershell
dotnet test manager\HideAnyWindowManager.sln
```

Expected: 3 passed, 0 failed.

- [ ] **Step 5: Commit**

```powershell
git add manager
git commit -m "feat(manager): ServiceController with mutex liveness check + AHK UIA launch"
```

---

## Task 5: `ProcessEnumerator` — visible top-level windows for the picker

**Files:**
- Create: `manager/src/HideAnyWindowManager/Util/Win32.cs`
- Create: `manager/src/HideAnyWindowManager/Services/ProcessEnumerator.cs`

The picker shows one row per **process that has at least one visible top-level window** (deduped by exe basename). This is what makes the list usable — without dedup, you'd see five Chrome rows for five Chrome windows, etc.

- [ ] **Step 1: Win32 P/Invoke declarations**

`manager/src/HideAnyWindowManager/Util/Win32.cs`:

```csharp
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace HideAnyWindowManager.Util;

internal static class Win32
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    public const uint GW_OWNER = 4;

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool QueryFullProcessImageNameW(IntPtr hProcess, uint dwFlags, StringBuilder lpExeName, ref uint lpdwSize);

    public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
}
```

- [ ] **Step 2: Implement `ProcessEnumerator`**

`manager/src/HideAnyWindowManager/Services/ProcessEnumerator.cs`:

```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Util;

namespace HideAnyWindowManager.Services;

public sealed class ProcessEnumerator
{
    /// <summary>Enumerates all visible top-level (un-owned) windows, dedupes by owning process exe,
    /// and returns one entry per exe with a friendly name (the first window's title or the exe name).</summary>
    public IReadOnlyList<WindowedProcessInfo> EnumerateWindowedProcesses(IReadOnlyCollection<string> alreadyMonitoredExes)
    {
        var byExe = new Dictionary<string, WindowedProcessInfo>(StringComparer.OrdinalIgnoreCase);
        var monitoredSet = new HashSet<string>(alreadyMonitoredExes, StringComparer.OrdinalIgnoreCase);

        Win32.EnumWindows((hWnd, _) =>
        {
            if (!Win32.IsWindowVisible(hWnd)) return true;
            if (Win32.GetWindow(hWnd, Win32.GW_OWNER) != IntPtr.Zero) return true; // skip owned (e.g. dialogs)
            int len = Win32.GetWindowTextLength(hWnd);
            if (len == 0) return true; // skip windows with no title (system, hidden helpers)

            var titleBuf = new StringBuilder(len + 1);
            Win32.GetWindowText(hWnd, titleBuf, titleBuf.Capacity);
            var title = titleBuf.ToString();

            Win32.GetWindowThreadProcessId(hWnd, out uint pid);
            if (pid == 0) return true;

            var (exe, fullPath) = GetProcessImage(pid);
            if (string.IsNullOrEmpty(exe)) return true;

            if (!byExe.ContainsKey(exe))
            {
                byExe[exe] = new WindowedProcessInfo
                {
                    Exe = exe,
                    Name = string.IsNullOrEmpty(title) ? exe : title,
                    FullPath = fullPath,
                    AlreadyMonitored = monitoredSet.Contains(exe),
                };
            }
            return true;
        }, IntPtr.Zero);

        return byExe.Values.OrderBy(p => p.Name, StringComparer.OrdinalIgnoreCase).ToList();
    }

    private static (string exe, string fullPath) GetProcessImage(uint pid)
    {
        var hProc = Win32.OpenProcess(Win32.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (hProc == IntPtr.Zero) return ("", "");
        try
        {
            var buf = new StringBuilder(1024);
            uint size = (uint)buf.Capacity;
            if (!Win32.QueryFullProcessImageNameW(hProc, 0, buf, ref size))
                return ("", "");
            var fullPath = buf.ToString();
            return (Path.GetFileName(fullPath).ToLowerInvariant(), fullPath);
        }
        finally
        {
            Win32.CloseHandle(hProc);
        }
    }
}
```

- [ ] **Step 3: Manual smoke check**

Add a quick sanity test in MainWindow (delete after — this is throwaway):

In `MainWindow.xaml.cs`, replace `myButton_Click` body:

```csharp
private void myButton_Click(object sender, RoutedEventArgs e)
{
    var enumerator = new HideAnyWindowManager.Services.ProcessEnumerator();
    var procs = enumerator.EnumerateWindowedProcesses(System.Array.Empty<string>());
    var msg = string.Join("\n", procs.Select(p => $"{p.Name}  ({p.Exe})"));
    myButton.Content = $"{procs.Count} windowed processes — see debug output";
    System.Diagnostics.Debug.WriteLine(msg);
}
```

Run the app (`dotnet run --project manager\src\HideAnyWindowManager`). Click the button. Expected: button text changes to a count, and `Debug.WriteLine` output (visible if running from Visual Studio's Output window, or via `dotnet run --verbosity normal`) shows a list including any apps you have open. Confirm:
- ✅ Magnifier is in the list if open
- ✅ Notepad/Calculator/etc are in the list if open
- ✅ No SYSTEM or empty-title rows
- ✅ Each exe appears at most once

Revert the throwaway change (we'll do it properly in the picker dialog).

- [ ] **Step 4: Commit**

```powershell
git add manager
git commit -m "feat(manager): Win32 P/Invoke + ProcessEnumerator (dedupes by exe)"
```

---

## Task 6: Main window — XAML structural layout

**Files:**
- Modify: `manager/src/HideAnyWindowManager/MainWindow.xaml`
- Create: `manager/src/HideAnyWindowManager/Util/ObservableObject.cs`
- Create: `manager/src/HideAnyWindowManager/ViewModels/RuleViewModel.cs`
- Create: `manager/src/HideAnyWindowManager/ViewModels/MainViewModel.cs`

The XAML translates the approved mockup into structural WinUI 3 controls. We deliberately use **default WinUI 3 styling** for v1 — `ToggleSwitch`, `Button`, `ListView`, `TextBlock`. The mockup's exact icon gradients and pixel-perfect spacing are deferred. Acrylic title bar + Mica are nice-to-have polish.

- [ ] **Step 1: Tiny `ObservableObject` base**

`manager/src/HideAnyWindowManager/Util/ObservableObject.cs`:

```csharp
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace HideAnyWindowManager.Util;

public abstract class ObservableObject : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected void SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    protected void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
```

- [ ] **Step 2: `RuleViewModel`**

`manager/src/HideAnyWindowManager/ViewModels/RuleViewModel.cs`:

```csharp
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Util;

namespace HideAnyWindowManager.ViewModels;

public sealed class RuleViewModel : ObservableObject
{
    private bool _enabled;
    public string Id { get; }
    public string Exe { get; }
    public string Name { get; set; }

    public bool Enabled
    {
        get => _enabled;
        set => SetField(ref _enabled, value);
    }

    /// <summary>First letter of Name, used for the placeholder square icon.</summary>
    public string Initial => string.IsNullOrEmpty(Name) ? "?" : Name.Substring(0, 1).ToUpperInvariant();

    public RuleViewModel(Rule r)
    {
        Id = r.Id; Exe = r.Exe; Name = r.Name; _enabled = r.Enabled;
    }

    public Rule ToModel() => new() { Id = Id, Exe = Exe, Name = Name, Enabled = Enabled };
}
```

- [ ] **Step 3: `MainViewModel` — observable state container**

`manager/src/HideAnyWindowManager/ViewModels/MainViewModel.cs`:

```csharp
using System.Collections.ObjectModel;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Util;

namespace HideAnyWindowManager.ViewModels;

public sealed class MainViewModel : ObservableObject
{
    private bool _isServiceRunning;
    private RuleViewModel? _selectedRule;

    public ObservableCollection<RuleViewModel> Rules { get; } = new();

    public bool IsServiceRunning
    {
        get => _isServiceRunning;
        set { SetField(ref _isServiceRunning, value); Raise(nameof(StatusText)); Raise(nameof(ServiceButtonText)); }
    }

    public RuleViewModel? SelectedRule
    {
        get => _selectedRule;
        set { SetField(ref _selectedRule, value); Raise(nameof(CanRemove)); }
    }

    public bool CanRemove => SelectedRule != null;
    public string StatusText => IsServiceRunning ? "Service running" : "Service stopped";
    public string ServiceButtonText => IsServiceRunning ? "Stop service" : "Start service";

    public void LoadFrom(Config cfg)
    {
        Rules.Clear();
        foreach (var r in cfg.Rules) Rules.Add(new RuleViewModel(r));
    }

    public Config ToConfig(string serviceState)
    {
        var cfg = new Config { ServiceState = serviceState };
        foreach (var r in Rules) cfg.Rules.Add(r.ToModel());
        return cfg;
    }
}
```

- [ ] **Step 4: `MainWindow.xaml`**

Replace the contents of `manager/src/HideAnyWindowManager/MainWindow.xaml`:

```xml
<Window
    x:Class="HideAnyWindowManager.MainWindow"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:vm="using:HideAnyWindowManager.ViewModels"
    Title="Hide Any Window">
    <Grid Padding="0">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Toolbar -->
        <Grid Padding="20,18,20,10" Grid.Row="0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="Monitored apps" FontSize="20" FontWeight="SemiBold" VerticalAlignment="Center"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal" Spacing="8">
                <Button x:Name="AddButton" Content="+ Add" Style="{StaticResource AccentButtonStyle}" Click="AddButton_Click"/>
                <Button x:Name="RemoveButton" Content="Remove" Click="RemoveButton_Click" IsEnabled="False"/>
            </StackPanel>
        </Grid>

        <!-- Rule list -->
        <ListView x:Name="RulesList" Grid.Row="1" Padding="12,4,12,16" SelectionMode="Single"
                  SelectionChanged="RulesList_SelectionChanged">
            <ListView.ItemTemplate>
                <DataTemplate x:DataType="vm:RuleViewModel">
                    <Grid Padding="6,8" ColumnSpacing="14">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <Border Width="28" Height="28" CornerRadius="6" Background="#4F7CFF">
                            <TextBlock Text="{x:Bind Initial}" Foreground="White" HorizontalAlignment="Center"
                                       VerticalAlignment="Center" FontWeight="SemiBold"/>
                        </Border>
                        <TextBlock Grid.Column="1" Text="{x:Bind Name}" VerticalAlignment="Center" FontSize="14"/>
                        <ToggleSwitch Grid.Column="2" IsOn="{x:Bind Enabled, Mode=TwoWay}"
                                      OnContent="" OffContent="" Toggled="RuleToggle_Toggled"/>
                    </Grid>
                </DataTemplate>
            </ListView.ItemTemplate>
        </ListView>

        <!-- Footer (service status + Stop/Start) -->
        <Grid Grid.Row="2" Padding="20,12,20,14" Background="{ThemeResource SystemControlBackgroundBaseLowBrush}">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Orientation="Horizontal" Spacing="8" VerticalAlignment="Center">
                <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="Gray"/>
                <TextBlock x:Name="StatusLabel" Text="Service stopped" FontWeight="SemiBold"/>
            </StackPanel>
            <Button Grid.Column="1" x:Name="ServiceButton" Content="Start service" Click="ServiceButton_Click"/>
        </Grid>
    </Grid>
</Window>
```

- [ ] **Step 5: Stub `MainWindow.xaml.cs` so the project builds**

`manager/src/HideAnyWindowManager/MainWindow.xaml.cs`:

```csharp
using HideAnyWindowManager.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HideAnyWindowManager;

public sealed partial class MainWindow : Window
{
    public MainViewModel ViewModel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        RulesList.ItemsSource = ViewModel.Rules;
    }

    // Wired up properly in Task 7
    private void AddButton_Click(object sender, RoutedEventArgs e) { }
    private void RemoveButton_Click(object sender, RoutedEventArgs e) { }
    private void RulesList_SelectionChanged(object sender, SelectionChangedEventArgs e) { }
    private void RuleToggle_Toggled(object sender, RoutedEventArgs e) { }
    private void ServiceButton_Click(object sender, RoutedEventArgs e) { }
}
```

- [ ] **Step 6: Build and run — verify the layout**

```powershell
dotnet run --project manager\src\HideAnyWindowManager
```

Expected:
- A window opens.
- Top: "Monitored apps" header on the left, "+ Add" (accent-blue) and "Remove" (greyed out) buttons on the right.
- Middle: empty list area.
- Bottom: grey footer bar with a grey dot, "Service stopped" text, and "Start service" button on the right.

If the layout looks right (empty list, all controls present and enabled-state correct), Task 6 is done. Don't worry about the rule rows being empty — Task 7 wires up the data.

- [ ] **Step 7: Commit**

```powershell
git add manager
git commit -m "feat(manager): main window XAML + observable view-models"
```

---

## Task 7: Main window code-behind — wire up data, Add/Remove/toggle

**Files:**
- Modify: `manager/src/HideAnyWindowManager/MainWindow.xaml.cs`
- Modify: `manager/src/HideAnyWindowManager/App.xaml.cs`

- [ ] **Step 1: Compose services in `App.xaml.cs`**

Replace the `OnLaunched` method and add fields:

```csharp
using Microsoft.UI.Xaml;
using HideAnyWindowManager.Services;

namespace HideAnyWindowManager;

public partial class App : Application
{
    public static ConfigStore ConfigStore { get; } = new();
    public static ServiceController ServiceController { get; } = new();
    public static ProcessEnumerator ProcessEnumerator { get; } = new();

    private Window? _mainWindow;

    public App() { InitializeComponent(); }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _mainWindow = new MainWindow();
        _mainWindow.Activate();
    }
}
```

(Static singletons keep this simple — no DI container needed at this scale.)

- [ ] **Step 2: Replace the stub `MainWindow.xaml.cs`**

```csharp
using System;
using System.Linq;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Services;
using HideAnyWindowManager.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HideAnyWindowManager;

public sealed partial class MainWindow : Window
{
    public MainViewModel ViewModel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        RulesList.ItemsSource = ViewModel.Rules;
        _ = LoadAsync();
    }

    private async System.Threading.Tasks.Task LoadAsync()
    {
        var cfg = await App.ConfigStore.LoadAsync();
        ViewModel.LoadFrom(cfg);
    }

    private void RulesList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        ViewModel.SelectedRule = RulesList.SelectedItem as RuleViewModel;
        RemoveButton.IsEnabled = ViewModel.CanRemove;
    }

    private void RuleToggle_Toggled(object sender, RoutedEventArgs e)
    {
        // The two-way binding has already updated the VM; persist.
        SaveDebounced();
    }

    private void RemoveButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectedRule is null) return;
        ViewModel.Rules.Remove(ViewModel.SelectedRule);
        ViewModel.SelectedRule = null;
        RemoveButton.IsEnabled = false;
        SaveDebounced();
    }

    private async void AddButton_Click(object sender, RoutedEventArgs e)
    {
        var existingExes = ViewModel.Rules.Select(r => r.Exe).ToList();
        var dialog = new AddPickerDialog(App.ProcessEnumerator, existingExes)
        {
            XamlRoot = ((FrameworkElement)Content).XamlRoot,
        };
        var result = await dialog.ShowAsync();
        if (result == ContentDialogResult.Primary && dialog.SelectedProcess is { } proc)
        {
            ViewModel.Rules.Add(new RuleViewModel(new Rule
            {
                Id = Rule.IdFromExe(proc.Exe),
                Exe = proc.Exe,
                Name = proc.Name,
                Enabled = true,
            }));
            SaveDebounced();
        }
    }

    private void ServiceButton_Click(object sender, RoutedEventArgs e)
    {
        // Implemented in Task 9
    }

    private void SaveDebounced()
    {
        var cfg = ViewModel.ToConfig(ViewModel.IsServiceRunning ? "running" : "stopped");
        App.ConfigStore.ScheduleSave(cfg);
    }
}
```

(Note: the AddButton_Click references `AddPickerDialog`, which is created in Task 8. The build will fail until Task 8 lands — that's expected. If you want to land Task 7 in isolation, comment out the AddButton_Click body and re-enable it after Task 8.)

- [ ] **Step 3: Manual verification (after Task 8 also lands)**

Defer end-to-end verification to Task 10. For now, confirm the project still compiles after Task 8:

```powershell
dotnet build manager\HideAnyWindowManager.sln
```

Expected: success.

- [ ] **Step 4: Commit (deferred until Task 8 also compiles)**

Bundle the commit with Task 8 since they're interdependent. Skip standalone commit here.

---

## Task 8: Add picker `ContentDialog`

**Files:**
- Create: `manager/src/HideAnyWindowManager/AddPickerDialog.xaml`
- Create: `manager/src/HideAnyWindowManager/AddPickerDialog.xaml.cs`

- [ ] **Step 1: `AddPickerDialog.xaml`**

```xml
<ContentDialog
    x:Class="HideAnyWindowManager.AddPickerDialog"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:m="using:HideAnyWindowManager.Models"
    Title="Add app to monitor"
    PrimaryButtonText="Add"
    CloseButtonText="Cancel"
    DefaultButton="Primary"
    IsPrimaryButtonEnabled="False">
    <Grid Width="440" RowSpacing="8">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" ColumnSpacing="8">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="SearchBox" PlaceholderText="Search visible windows..." TextChanged="SearchBox_TextChanged"/>
            <TextBlock Grid.Column="1" x:Name="CountLabel" VerticalAlignment="Center" FontSize="11" Foreground="Gray"/>
        </Grid>

        <ListView Grid.Row="1" x:Name="PickList" Height="300" SelectionMode="Single"
                  SelectionChanged="PickList_SelectionChanged" DoubleTapped="PickList_DoubleTapped">
            <ListView.ItemTemplate>
                <DataTemplate x:DataType="m:WindowedProcessInfo">
                    <Grid Padding="4,6" ColumnSpacing="12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Width="26" Height="26" CornerRadius="5" Background="#4F7CFF">
                            <TextBlock Text="?" Foreground="White" HorizontalAlignment="Center"
                                       VerticalAlignment="Center" FontWeight="SemiBold"/>
                        </Border>
                        <StackPanel Grid.Column="1">
                            <TextBlock Text="{x:Bind Name}" FontSize="13" FontWeight="SemiBold"/>
                            <TextBlock FontSize="11" Foreground="Gray">
                                <Run Text="{x:Bind Exe}"/>
                                <Run Text="{x:Bind AlreadyMonitoredAnnotation}"/>
                            </TextBlock>
                        </StackPanel>
                    </Grid>
                </DataTemplate>
            </ListView.ItemTemplate>
        </ListView>
    </Grid>
</ContentDialog>
```

- [ ] **Step 2: Add the annotation property to `WindowedProcessInfo`**

Modify `manager/src/HideAnyWindowManager/Models/WindowedProcessInfo.cs` to add a derived property the XAML binds to:

```csharp
public string AlreadyMonitoredAnnotation => AlreadyMonitored ? " · already monitored" : "";
```

- [ ] **Step 3: `AddPickerDialog.xaml.cs`**

```csharp
using System.Collections.Generic;
using System.Linq;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace HideAnyWindowManager;

public sealed partial class AddPickerDialog : ContentDialog
{
    private readonly List<WindowedProcessInfo> _all;
    public WindowedProcessInfo? SelectedProcess { get; private set; }

    public AddPickerDialog(ProcessEnumerator enumerator, IReadOnlyCollection<string> alreadyMonitoredExes)
    {
        InitializeComponent();
        _all = enumerator.EnumerateWindowedProcesses(alreadyMonitoredExes).ToList();
        ApplyFilter("");
    }

    private void ApplyFilter(string text)
    {
        var filtered = string.IsNullOrWhiteSpace(text)
            ? _all
            : _all.Where(p => p.Name.Contains(text, System.StringComparison.OrdinalIgnoreCase)
                          || p.Exe.Contains(text, System.StringComparison.OrdinalIgnoreCase)).ToList();
        PickList.ItemsSource = filtered;
        CountLabel.Text = $"{filtered.Count} windows";
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
        => ApplyFilter(SearchBox.Text);

    private void PickList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        SelectedProcess = PickList.SelectedItem as WindowedProcessInfo;
        IsPrimaryButtonEnabled = SelectedProcess != null && !SelectedProcess.AlreadyMonitored;
    }

    private void PickList_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (SelectedProcess != null && !SelectedProcess.AlreadyMonitored)
            Hide(ContentDialogResult.Primary);
    }
}
```

- [ ] **Step 4: Build and visually verify**

```powershell
dotnet run --project manager\src\HideAnyWindowManager
```

Open some apps (Notepad, Calculator, Magnifier) before clicking Add. Then click "+ Add". Expected:
- A modal dialog appears, dimming the main window.
- Search box at top, list showing your open apps.
- Counter shows e.g. "5 windows".
- Add button (primary) starts disabled. Clicking a row enables it.
- Typing in the search box filters live.
- Double-clicking a row closes the dialog and adds the app to the main list.
- Clicking Cancel closes without adding.

- [ ] **Step 5: Commit (Tasks 7 + 8 together)**

```powershell
git add manager
git commit -m "feat(manager): main window wiring + Add picker dialog"
```

---

## Task 9: Service liveness watcher + Stop/Start button

**Files:**
- Modify: `manager/src/HideAnyWindowManager/MainWindow.xaml.cs`

The footer dot/text/button must reflect three system states ("process gone", "process running but paused", "process running and active") collapsed into the two user states ("stopped", "running") per the spec's footer-display rule.

- [ ] **Step 1: Add the timer + state evaluation**

Append to `MainWindow.xaml.cs`:

```csharp
using Microsoft.UI.Xaml.Media;
using Windows.UI;

// inside MainWindow class:

private Microsoft.UI.Xaml.DispatcherTimer? _statusTimer;

private void StartStatusWatch()
{
    _statusTimer = new Microsoft.UI.Xaml.DispatcherTimer
    {
        Interval = System.TimeSpan.FromSeconds(1),
    };
    _statusTimer.Tick += (_, __) => RefreshStatus();
    _statusTimer.Start();
    RefreshStatus();
}

private async void RefreshStatus()
{
    bool mutex = App.ServiceController.IsServiceRunning();
    var cfg = await App.ConfigStore.LoadAsync();
    bool effective = mutex && cfg.ServiceState == "running";

    ViewModel.IsServiceRunning = effective;
    StatusDot.Fill = new SolidColorBrush(effective
        ? Color.FromArgb(0xFF, 0x2E, 0x9C, 0x4F)
        : Color.FromArgb(0xFF, 0x88, 0x88, 0x88));
    StatusLabel.Text = ViewModel.StatusText;
    ServiceButton.Content = ViewModel.ServiceButtonText;
}
```

- [ ] **Step 2: Wire `ServiceButton_Click`**

Replace the empty `ServiceButton_Click` body:

```csharp
private async void ServiceButton_Click(object sender, RoutedEventArgs e)
{
    var cfg = await App.ConfigStore.LoadAsync();
    bool mutex = App.ServiceController.IsServiceRunning();

    if (!mutex)
    {
        // Process not running -> ensure config says "running" then launch.
        cfg.ServiceState = "running";
        await App.ConfigStore.SaveImmediateAsync(cfg);
        if (!App.ServiceController.TryStartService())
        {
            var dlg = new ContentDialog
            {
                Title = "Couldn't start service",
                Content = "AutoHotkey64_UIA.exe or service\\main.ahk not found in expected locations. " +
                          "Verify AHK v2 is installed at C:\\Program Files\\AutoHotkey\\v2 and that the " +
                          "manager exe sits next to the service folder.",
                CloseButtonText = "OK",
                XamlRoot = ((FrameworkElement)Content).XamlRoot,
            };
            await dlg.ShowAsync();
        }
    }
    else if (cfg.ServiceState == "running")
    {
        // Process running, currently active -> pause.
        cfg.ServiceState = "stopped";
        await App.ConfigStore.SaveImmediateAsync(cfg);
    }
    else
    {
        // Process running, paused -> resume.
        cfg.ServiceState = "running";
        await App.ConfigStore.SaveImmediateAsync(cfg);
    }
    RefreshStatus();
}
```

- [ ] **Step 3: Start the watcher in the constructor**

Append to the `MainWindow()` constructor:

```csharp
StartStatusWatch();
```

- [ ] **Step 4: Build, run, manual verify**

```powershell
dotnet run --project manager\src\HideAnyWindowManager
```

With the AHK service NOT running, expected:
- Footer shows grey dot, "Service stopped", "Start service" button.
- Click Start service → AHK service launches (no UAC prompt since UIA), within ~1s footer flips to green dot + "Service running" + "Stop service".

With the AHK service running, expected:
- Click Stop service → footer flips to "Service stopped" within 1s. (Underneath, the AHK service stays alive but pauses — verify in `Get-Process AutoHotkey*`.)
- Click Start service → flips back to "Service running".

- [ ] **Step 5: Commit**

```powershell
git add manager
git commit -m "feat(manager): service liveness watcher + Stop/Start button (3-state collapse)"
```

---

## Task 10: End-to-end validation + README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run the full validation matrix manually**

With both apps available (manager built, service exe path correct):

| # | Action | Expected |
|---|---|---|
| 1 | Open manager from `bin\Debug\...\HideAnyWindowManager.exe` (or `dotnet run`). | Window opens, list initially populated from any existing config.json. |
| 2 | Click + Add → pick Magnifier → click Add. | Magnifier row appears in main list with toggle ON. Within ~1s, the AHK service hides Magnifier. |
| 3 | Toggle Magnifier OFF. | Within ~1s, Magnifier reappears (visible + taskbar back). Toggle stays in the off state. |
| 4 | Toggle ON again. | Magnifier vanishes again. |
| 5 | Select the Magnifier row → click Remove. | Row deleted. Magnifier reappears (rule was last hiding it). |
| 6 | Stop service via footer. | Green dot → grey, label → "Service stopped". All hidden windows reappear. |
| 7 | Start service via footer. | Reverse — flips green, configured rules re-engage. |
| 8 | Close manager (X button). | Manager exits. AHK service KEEPS RUNNING. Configured windows stay hidden. |
| 9 | Reopen manager. | Reflects current state (rules + running indicator). |
| 10 | Add an app already monitored from the picker. | Row appears with " · already monitored". Add button is disabled while that row is selected. |

- [ ] **Step 2: Replace the README's "Configuration" section with manager instructions**

Open `README.md`. Find the "Configuration" section (currently describes editing config.json directly). Replace its body with:

```markdown
## Configuration

Configuration lives at `%APPDATA%\HideAnyWindow\config.json`. The **manager
app** is the supported way to edit it — see `manager/`. Direct JSON editing
still works for headless setups (the AHK service watches the file either way).

### Running the manager

After building (`dotnet build manager\HideAnyWindowManager.sln`):

```
manager\src\HideAnyWindowManager\bin\Debug\net8.0-windows10.0.19041.0\win-x64\HideAnyWindowManager.exe
```

Or `dotnet run --project manager\src\HideAnyWindowManager` from the repo root.

The manager runs un-elevated. It reads/writes the shared config.json and
detects whether the service is alive via the `HideAnyWindow_Service_Running`
named mutex. When you click "Start service" from the footer, the manager
launches the AHK service via `AutoHotkey64_UIA.exe` — no UAC prompt.
```

- [ ] **Step 3: Append a manager validation section**

At the end of `README.md`:

```markdown
## Validation results — Phase B manager

Tested on Windows 11 Pro, .NET 8 SDK, Windows App SDK 1.5+.

| # | Scenario | Result |
|---|---|---|
| 1 | Manager opens, shows existing rules | ✅ |
| 2 | Add Magnifier via picker → service hides | ✅ |
| 3 | Toggle off → service restores | ✅ |
| 4 | Toggle on → service re-hides | ✅ |
| 5 | Remove rule → service restores | ✅ |
| 6 | Stop service via footer | ✅ |
| 7 | Start service via footer (auto-launch when down) | ✅ |
| 8 | Manager close doesn't affect service | ✅ |
| 9 | Reopen manager reflects current state | ✅ |
| 10 | "already monitored" annotation in picker | ✅ |
```

(Replace `✅` with `❌` plus a note for any test that doesn't pass — debug those before declaring Plan B-2 done.)

- [ ] **Step 4: Commit**

```powershell
git add README.md
git commit -m "docs(manager): phase B-2 validation matrix; manager is now the recommended config UI"
```

---

## Self-review summary

**1. Spec coverage:**

- Manager UI components (main window, picker): Tasks 6, 7, 8 ✅
- ConfigStore (atomic writes, debounce): Task 3 ✅
- ServiceController (mutex check, launch via UIA AHK): Task 4 ✅ (note: the spec said launch via `Verb=runas`; we use `AutoHotkey64_UIA.exe` instead — discovered to be cleaner during service validation. Plan reflects current reality.)
- ProcessEnumerator (visible windowed processes, dedup by exe): Task 5 ✅
- Liveness via mutex polling: Task 9 ✅
- Footer-display rule (3 system states → 2 user states): Task 9 Step 1 ✅
- Stop service = `serviceState: "stopped"` write (not process kill): Task 9 Step 2 ✅
- Start service = launch if mutex absent, else flip state: Task 9 Step 2 ✅
- "already monitored" picker annotation: Task 8 Step 2 + Task 5's `AlreadyMonitored` field ✅
- Single-instance for the manager: NOT in this plan. The spec mentions it as an edge case (test #10 in the spec). Deferred — not critical for v1; Windows lets multiple manager instances run, they all see the same config file. Worst-case impact: confusing if user opens two and edits in both, but `ScheduleSave` debounces and the file watcher in the service merges either way. Adding single-instance later is straightforward (Windows App SDK provides `AppInstance.GetCurrent` / `RedirectActivationToAsync`).

**2. Placeholder scan:** No "TBD"/"TODO"/"add appropriate" patterns. Validation result table uses ✅ as a placeholder for the user to confirm — same pattern as Phase A/B service plans, intentional.

**3. Type/name consistency:**
- `Config.ServiceState` (string), `Config.Rules` (List&lt;Rule&gt;), `Rule.Id/Exe/Name/Enabled` — used consistently in Tasks 2, 3, 6, 7.
- `ConfigStore.LoadAsync()` / `SaveImmediateAsync(Config)` / `ScheduleSave(Config)` — defined Task 3, called consistently in Tasks 7, 9.
- `ServiceController.IsServiceRunning()` / `TryStartService()` — defined Task 4, called Task 9.
- `ProcessEnumerator.EnumerateWindowedProcesses(IReadOnlyCollection<string>)` — defined Task 5, called Task 8.
- `WindowedProcessInfo.AlreadyMonitored` / `AlreadyMonitoredAnnotation` — defined Tasks 2/8, used in XAML Task 8.
- `MainViewModel.LoadFrom(Config)` / `ToConfig(string serviceState)` / `Rules` (ObservableCollection&lt;RuleViewModel&gt;) / `IsServiceRunning` / `SelectedRule` — defined Task 6, used Task 7. ✅

All consistent.

**4. Notable spec drifts called out in commit messages or comments:**
- Service launch uses `AutoHotkey64_UIA.exe` (no UAC) instead of `Verb=runas` from the spec. Documented in `ServiceController` xmldoc and committed as such.
- Single-instance manager check is deferred — noted above.
