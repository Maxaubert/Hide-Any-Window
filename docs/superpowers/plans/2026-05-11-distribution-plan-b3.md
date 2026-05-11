# Distribution (Plan B-3) — self-contained installable bundle

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Produce a downloadable bundle so an end user can install `Hide Any Window` in one step (one UAC click) without installing .NET, Windows App SDK, or AutoHotkey separately.

**Architecture:**
- `HideAnyWindowManager.exe` — published self-contained (.NET 8 + Windows App SDK 2.0 bundled).
- `HideAnyWindowService.exe` — `service/main.ahk` compiled via Ahk2Exe with the AutoHotkey64_UIA.exe base, then signed with a self-signed code-signing cert. UIAccess manifest is inherited from the AHK base.
- `HideAnyWindowSetup.ps1` — single-file installer that runs PowerShell, generates+installs the cert, signs the service exe, copies both exes to `C:\Program Files\HideAnyWindow\`, drops a Start Menu shortcut, and offers to enable the at-logon Task Scheduler entry.
- `dist/` build directory holds the staging area + final `HideAnyWindow-Setup.zip`.

**Tech stack:** dotnet publish with `<WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>`, `Ahk2Exe.exe` (in `C:\Program Files\AutoHotkey\Compiler\`), `New-SelfSignedCertificate` + `signtool.exe` for cert + signing, PowerShell for the installer.

**Note on testing:** Since the bundle's job is to install onto a clean machine, full validation requires a clean Windows VM. We can't fully test that here, so the plan validates each stage in isolation (compile produces an exe; signing reports OK; signed exe runs UIAccess from Program Files; installer reaches its own success branches).

**Branch:** `distribution` (worktree). Once validated, rebase or merge into `main`.

---

## File Structure

New top-level `dist/` directory in the repo. Build outputs land here. Source files for the build pipeline:

```
dist/
  build.ps1               orchestrator: clean → compile → sign → publish → zip
  installer/
    HideAnyWindowSetup.ps1   runs on the user's machine
    HideAnyWindow.cer        public certificate (committed; private key never committed)
  staging/                build output, gitignored
  HideAnyWindow-Setup.zip the final artifact, gitignored
```

The private key (`.pfx`) lives in a developer-only path NOT committed; build.ps1 either generates it on first run or reuses an existing one.

---

## Task 1: Self-contained manager publish

**Files:**
- Modify: `manager/src/HideAnyWindowManager/HideAnyWindowManager.csproj`

The csproj currently builds a framework-dependent app. Add the properties needed for self-contained WinUI 3 publish.

- [ ] **Step 1: Add self-contained properties to the csproj**

Inside the first `<PropertyGroup>` add:

```xml
<SelfContained>true</SelfContained>
<WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>
<PublishReadyToRun>true</PublishReadyToRun>
```

- [ ] **Step 2: Verify publish builds**

Run from repo root:

```powershell
dotnet publish manager\src\HideAnyWindowManager\HideAnyWindowManager.csproj `
  -c Release -r win-x64 -o dist\staging\manager
```

Expected: command completes; `dist\staging\manager\HideAnyWindowManager.exe` exists; `Microsoft.WindowsAppRuntime.*.dll` files are in the output folder. The folder will be ~150 MB.

If publish fails complaining about `<RuntimeIdentifier>` already being set in the csproj — we already removed that in earlier work, so it shouldn't reoccur. If it does, also pass `--no-self-contained-trim` or check the csproj.

- [ ] **Step 3: Smoke-test the published exe** (manual)

Double-click `dist\staging\manager\HideAnyWindowManager.exe`. Expected: UAC prompt → Yes → manager opens normally with all functionality (theme switching, picker, settings dialog).

If this works, the self-contained publish is solid and we can move on. If not, debug the WinAppSDK self-contained side — typical issues are missing native dependencies that need explicit `<RuntimeHostConfigurationOption>` properties.

- [ ] **Step 4: Commit**

```powershell
git add manager\src\HideAnyWindowManager\HideAnyWindowManager.csproj
git commit -m "build(manager): self-contained publish (.NET 8 + WinAppSDK bundled)"
```

(`dist/` is gitignored; we'll add it in Task 5.)

---

## Task 2: Compile the service with Ahk2Exe

**Files:**
- Create: `dist/build.ps1` (initial version with just the compile step)

- [ ] **Step 1: Create the build script with the Ahk2Exe step**

`dist/build.ps1`:

```powershell
# Hide Any Window — distribution build script
# Run from repo root: powershell -ExecutionPolicy Bypass -File dist\build.ps1

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path "$PSScriptRoot\.."
$staging  = Join-Path $repoRoot 'dist\staging'
$ahk2Exe  = 'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe'
$ahkBaseUia = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe'

if (-not (Test-Path $ahk2Exe))     { throw "Ahk2Exe.exe not found at $ahk2Exe" }
if (-not (Test-Path $ahkBaseUia))  { throw "AutoHotkey64_UIA.exe not found at $ahkBaseUia" }

# Clean previous staging
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null
New-Item -ItemType Directory -Path "$staging\service" | Out-Null

Write-Host "[1/4] Compiling service via Ahk2Exe..."
$serviceScript = Join-Path $repoRoot 'service\main.ahk'
$serviceExe    = Join-Path $staging 'service\HideAnyWindowService.exe'
& $ahk2Exe /in $serviceScript /out $serviceExe /base $ahkBaseUia
if ($LASTEXITCODE -ne 0) { throw "Ahk2Exe failed with exit $LASTEXITCODE" }
if (-not (Test-Path $serviceExe)) { throw "Service exe not produced at $serviceExe" }
Write-Host "       -> $serviceExe ($([math]::Round((Get-Item $serviceExe).Length / 1KB))KB)"

Write-Host "Done so far. Subsequent steps land in later tasks."
```

- [ ] **Step 2: Run it and confirm**

```powershell
powershell -ExecutionPolicy Bypass -File dist\build.ps1
```

Expected: `dist\staging\service\HideAnyWindowService.exe` exists, ~1–2 MB. If Ahk2Exe complains about includes (`#Include lib\JSON.ahk`), it usually pulls them in correctly because Ahk2Exe respects `#Include` paths relative to the script. Verify by checking the exe size — should be larger than just the AHK base (1.2 MB) by the script + JSON.ahk size.

- [ ] **Step 3: Smoke-test the compiled service** (manual)

Drop a config.json in `%APPDATA%\HideAnyWindow\` (or use existing). Right-click the compiled exe → Run as administrator. Confirm `service.log` shows `service starting (full lifecycle)`. Stop via Task Manager.

- [ ] **Step 4: Commit**

```powershell
git add dist\build.ps1
git commit -m "build: dist\build.ps1 with Ahk2Exe compile step for service"
```

---

## Task 3: Self-signed cert + signtool

**Files:**
- Modify: `dist/build.ps1` — add cert generation/load + signing steps
- Create: `dist/installer/HideAnyWindow.cer` — public cert exported (committed)
- The .pfx (private key) lives at `dist\.cert.pfx` and is **gitignored**

- [ ] **Step 1: Add cert generation + signing to build.ps1**

After the existing `[1/4] Compiling service...` block, append:

```powershell
$certPfx     = Join-Path $repoRoot 'dist\.cert.pfx'
$certCer     = Join-Path $repoRoot 'dist\installer\HideAnyWindow.cer'
$certSubject = 'CN=HideAnyWindowDev'
$certPwd     = ConvertTo-SecureString 'devpassword' -Force -AsPlainText

if (-not (Test-Path $certPfx)) {
    Write-Host "[2/4] No cert.pfx found — generating self-signed code-signing cert..."
    $cert = New-SelfSignedCertificate `
        -Type CodeSigning `
        -Subject $certSubject `
        -KeyUsage DigitalSignature `
        -KeyAlgorithm RSA -KeyLength 2048 `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -NotAfter (Get-Date).AddYears(5)
    Export-PfxCertificate -Cert $cert -FilePath $certPfx -Password $certPwd | Out-Null
    Export-Certificate -Cert $cert -FilePath $certCer | Out-Null
    Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force
    Write-Host "       -> $certPfx (private key, gitignored)"
    Write-Host "       -> $certCer (public cert, committed; installer trusts this)"
} else {
    Write-Host "[2/4] Reusing existing cert.pfx + .cer"
}

Write-Host "[3/4] Signing service exe..."
$signtool = (Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe' |
             Sort-Object FullName -Descending | Select-Object -First 1).FullName
if (-not $signtool) { throw "signtool.exe not found — install Windows 10 SDK (Smart Card / Code Signing tools component)" }
& $signtool sign /f $certPfx /p 'devpassword' /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $serviceExe
if ($LASTEXITCODE -ne 0) { throw "signtool sign failed with exit $LASTEXITCODE" }
Write-Host "       -> signed: $serviceExe"
```

(`/tr` adds an RFC3161 timestamp; without it the signature would be considered invalid after the cert expires. `digicert.com` is a free, widely-used timestamp server — substitute another if blocked.)

- [ ] **Step 2: Run build.ps1**

```powershell
powershell -ExecutionPolicy Bypass -File dist\build.ps1
```

Expected:
- `dist\.cert.pfx` created on first run
- `dist\installer\HideAnyWindow.cer` created on first run
- Service exe signed; signtool prints "Successfully signed: ..."

Verify the signature:

```powershell
Get-AuthenticodeSignature dist\staging\service\HideAnyWindowService.exe | Format-List
```

Expected: `Status : NotTrusted` (because the cert isn't in Trusted Root yet — that's the installer's job) and `SignerCertificate.Subject : CN=HideAnyWindowDev`.

- [ ] **Step 3: Verify .pfx is gitignored**

```powershell
git check-ignore dist\.cert.pfx
```

Expected: prints the path. If not, add `dist/.cert.pfx` to `.gitignore`.

Also extend `.gitignore` to ignore the staging/output:

```gitignore
dist/staging/
dist/HideAnyWindow-Setup.zip
dist/.cert.pfx
```

- [ ] **Step 4: Commit**

```powershell
git add dist\installer\HideAnyWindow.cer dist\build.ps1 .gitignore
git commit -m "build: self-signed cert generation + signtool integration"
```

(`.cer` is the public part — safe to commit. `.pfx` is the private key — gitignored.)

---

## Task 4: Add the manager publish step to build.ps1 + zip

**Files:**
- Modify: `dist/build.ps1`

- [ ] **Step 1: Append publish + zip steps**

At the end of `dist\build.ps1`, append:

```powershell
Write-Host "[4/4] Publishing manager (self-contained)..."
$managerCsproj = Join-Path $repoRoot 'manager\src\HideAnyWindowManager\HideAnyWindowManager.csproj'
$managerOut    = Join-Path $staging 'manager'
& dotnet publish $managerCsproj -c Release -r win-x64 -o $managerOut --nologo --verbosity minimal
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit $LASTEXITCODE" }
$managerExe = Join-Path $managerOut 'HideAnyWindowManager.exe'
if (-not (Test-Path $managerExe)) { throw "Manager exe not produced at $managerExe" }
Write-Host "       -> $managerOut ($([math]::Round((Get-ChildItem $managerOut -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB))MB)"

# Stage the installer + cert alongside the binaries
Copy-Item -Path (Join-Path $repoRoot 'dist\installer\*') -Destination $staging -Recurse

Write-Host "[5/5] Zipping..."
$zipPath = Join-Path $repoRoot 'dist\HideAnyWindow-Setup.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$staging\*" -DestinationPath $zipPath
Write-Host "       -> $zipPath ($([math]::Round((Get-Item $zipPath).Length / 1MB))MB)"

Write-Host ""
Write-Host "Done. Distributable: $zipPath" -ForegroundColor Green
```

- [ ] **Step 2: Run + confirm zip is produced**

```powershell
powershell -ExecutionPolicy Bypass -File dist\build.ps1
```

Expected: `dist\HideAnyWindow-Setup.zip` exists, ~150–200 MB. Inside it:
- `HideAnyWindowSetup.ps1`
- `HideAnyWindow.cer`
- `manager\HideAnyWindowManager.exe` + DLLs
- `service\HideAnyWindowService.exe`

- [ ] **Step 3: Commit**

```powershell
git add dist\build.ps1
git commit -m "build: full pipeline with manager publish + zip"
```

---

## Task 5: Installer script

**Files:**
- Create: `dist/installer/HideAnyWindowSetup.ps1`

The installer is what end users actually run. It needs to be self-explanatory, fail safely, and roll back nothing (just refuse to proceed if something's wrong).

- [ ] **Step 1: Write the installer**

`dist/installer/HideAnyWindowSetup.ps1`:

```powershell
# Hide Any Window — installer
# Run from the extracted ZIP folder: right-click → Run with PowerShell (UAC prompt expected).

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = 'C:\Program Files\HideAnyWindow'

function Step($n, $msg) { Write-Host "[$n] $msg" -ForegroundColor Cyan }

# --- Elevation check ---
$current = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Re-launching as administrator..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    exit
}

Step 1 "Trusting the bundled code-signing certificate"
$cerPath = Join-Path $here 'HideAnyWindow.cer'
if (-not (Test-Path $cerPath)) { throw "HideAnyWindow.cer not found beside the installer." }
Import-Certificate -FilePath $cerPath -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $cerPath -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

Step 2 "Copying files to $installRoot"
if (Test-Path $installRoot) {
    # Stop the service if it's running so we can overwrite it
    Get-Process -Name 'HideAnyWindowService','HideAnyWindowManager' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item -Path (Join-Path $here 'manager\*')  -Destination $installRoot -Recurse -Force
Copy-Item -Path (Join-Path $here 'service\HideAnyWindowService.exe') -Destination $installRoot -Force

Step 3 "Creating Start Menu shortcut"
$shortcut = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Hide Any Window.lnk"
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($shortcut)
$lnk.TargetPath = "$installRoot\HideAnyWindowManager.exe"
$lnk.WorkingDirectory = $installRoot
$lnk.Save()

Step 4 "Asking about logon autostart"
$ans = Read-Host "Start the Hide Any Window service automatically when you sign in? (y/N)"
if ($ans -match '^[Yy]') {
    schtasks /Create /TN 'HideAnyWindowService' /SC ONLOGON /RL HIGHEST `
        /TR "`"$installRoot\HideAnyWindowService.exe`"" /F | Out-Null
    Step 4 "  -> Task Scheduler entry created. Service will start at next logon."
} else {
    Step 4 "  -> Skipped autostart. You can enable it later from the manager's Settings page."
}

Step 5 "Done!"
Write-Host ""
Write-Host "Installed to: $installRoot" -ForegroundColor Green
Write-Host "Start Menu:   Hide Any Window" -ForegroundColor Green
Write-Host ""
Write-Host "Open the manager via the Start Menu, click Start service, and add apps to monitor."
Read-Host "Press Enter to close"
```

- [ ] **Step 2: Manually test the installer flow**

Either on a clean VM or carefully on the dev machine (it'll overwrite any existing install). After running:
- `C:\Program Files\HideAnyWindow\HideAnyWindowManager.exe` exists
- `C:\Program Files\HideAnyWindow\HideAnyWindowService.exe` exists
- `Get-AuthenticodeSignature 'C:\Program Files\HideAnyWindow\HideAnyWindowService.exe'` → Status: `Valid`
- Start Menu has "Hide Any Window"
- (If chosen) Task Scheduler shows `HideAnyWindowService` task

Open the manager via Start Menu → click Start service → confirm AHK service launches without UAC (UIAccess auto-elevation works because the cert is now in Trusted Root + Trusted Publisher).

- [ ] **Step 3: Commit**

```powershell
git add dist\installer\HideAnyWindowSetup.ps1
git commit -m "build(installer): one-step installer with cert, file copy, shortcut, optional autostart"
```

---

## Task 6: Update ServiceController to point at the installed service exe

**Files:**
- Modify: `manager/src/HideAnyWindowManager/Services/ServiceController.cs`

Currently `DefaultScriptPath` walks up from BaseDirectory looking for `service\main.ahk`. In the installed layout, both manager and service are siblings in `C:\Program Files\HideAnyWindow\`, and the service is now an `.exe`, not a script. Update both helpers.

- [ ] **Step 1: Update `DefaultScriptPath` and `DefaultAhkUiaPath`**

Replace those two methods:

```csharp
public static string DefaultAhkUiaPath()
{
    // Production: HideAnyWindowService.exe sits next to the manager exe.
    var sibling = System.IO.Path.Combine(System.AppContext.BaseDirectory, "HideAnyWindowService.exe");
    if (System.IO.File.Exists(sibling))
        return sibling;
    // Dev fallback: AutoHotkey64_UIA.exe from a system AHK install.
    return @"C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe";
}

public static string DefaultScriptPath()
{
    // Production: HideAnyWindowService.exe takes no script argument (script is embedded).
    var sibling = System.IO.Path.Combine(System.AppContext.BaseDirectory, "HideAnyWindowService.exe");
    if (System.IO.File.Exists(sibling))
        return "";   // signal: no script argument needed
    // Dev fallback: walk up to find service\main.ahk.
    var dir = new System.IO.DirectoryInfo(System.AppContext.BaseDirectory);
    while (dir != null)
    {
        var probe = System.IO.Path.Combine(dir.FullName, "service", "main.ahk");
        if (System.IO.File.Exists(probe))
            return probe;
        dir = dir.Parent;
    }
    return System.IO.Path.GetFullPath(System.IO.Path.Combine(System.AppContext.BaseDirectory, @"..\service\main.ahk"));
}
```

Update `TryStartService` to omit the script argument when production layout is detected:

```csharp
public bool TryStartService(string? scriptPath = null, string? ahkUiaPath = null)
{
    scriptPath ??= DefaultScriptPath();
    ahkUiaPath ??= DefaultAhkUiaPath();

    bool ahkOk = File.Exists(ahkUiaPath);
    bool scriptOk = string.IsNullOrEmpty(scriptPath) || File.Exists(scriptPath);
    Log($"TryStartService probed: ahk={ahkUiaPath} (exists={ahkOk})  script={scriptPath} (skip-if-empty, exists={scriptOk})");

    if (!ahkOk || !scriptOk)
    {
        Log("TryStartService aborting — required path missing");
        return false;
    }

    try
    {
        var psi = new ProcessStartInfo
        {
            FileName = ahkUiaPath,
            Arguments = string.IsNullOrEmpty(scriptPath) ? "" : "\"" + scriptPath + "\"",
            UseShellExecute = true,
        };
        var proc = Process.Start(psi);
        Log($"TryStartService Process.Start returned proc={proc?.Id.ToString() ?? "null"}");
        return proc != null;
    }
    catch (Exception ex)
    {
        Log($"TryStartService Process.Start threw: {ex.GetType().Name}: {ex.Message}");
        return false;
    }
}
```

Also update AutostartManager so its scheduled task points at the installed service exe directly (no script argument) when the production layout is in place:

In `AutostartManager.cs`, find the `TryEnable` body. The current line:

```csharp
var taskRun = $"\"{ahkUia}\" \"{script}\"";
```

Change to:

```csharp
var taskRun = string.IsNullOrEmpty(script)
    ? $"\"{ahkUia}\""
    : $"\"{ahkUia}\" \"{script}\"";
```

- [ ] **Step 2: Build and quick-test in dev (paths still resolve)**

```powershell
dotnet build manager\HideAnyWindowManager.sln
```

Expected: clean. The dev build will continue to use the AHK script path (since no sibling `HideAnyWindowService.exe` exists in `bin\Debug\`), so behaviour during normal development is unchanged.

- [ ] **Step 3: Re-publish + re-zip + reinstall + smoke-test**

```powershell
powershell -ExecutionPolicy Bypass -File dist\build.ps1
```

Then re-extract and re-run `HideAnyWindowSetup.ps1`. Open manager → Start service → confirm `HideAnyWindowService.exe` (NOT `AutoHotkey64_UIA.exe`) appears in `tasklist`.

- [ ] **Step 4: Commit**

```powershell
git add manager\src\HideAnyWindowManager\Services\ServiceController.cs `
        manager\src\HideAnyWindowManager\Services\AutostartManager.cs
git commit -m "feat(manager): launch installed HideAnyWindowService.exe in production layout (sibling to manager exe), fall back to AHK script in dev"
```

---

## Task 7: README install instructions for end users

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add an "Install" section to README.md**

Insert near the top, after the "Status" section:

```markdown
## Install (end users)

1. Download `HideAnyWindow-Setup.zip` from [Releases](#) (link to be filled in after first release).
2. Extract anywhere.
3. Right-click `HideAnyWindowSetup.ps1` → **Run with PowerShell**. Approve the UAC prompt.
4. The installer:
   - Trusts the bundled code-signing certificate (so the elevated service runs without further UAC prompts)
   - Copies the manager + service to `C:\Program Files\HideAnyWindow\`
   - Adds a Start Menu entry
   - Optionally schedules the service to start at logon (you'll be asked)
5. Open **Hide Any Window** from the Start Menu, click **Start service**, and use **+ Add** to pick apps to hide.

To uninstall: delete the install directory + the Task Scheduler entry (`schtasks /Delete /TN HideAnyWindowService /F`) + the Start Menu shortcut + the trusted cert (Manage Computer Certificates → Trusted Root → remove `HideAnyWindowDev`).
```

- [ ] **Step 2: Commit**

```powershell
git add README.md
git commit -m "docs: install instructions for the distributable"
```

---

## Self-review

**Spec coverage:**
- Self-contained manager exe: Task 1 ✅
- Compiled signed service exe with UIAccess: Tasks 2 + 3 ✅
- Self-signed cert generation + trust: Task 3 (gen) + Task 5 (install) ✅
- Installer with one-UAC flow: Task 5 ✅
- Files in `Program Files`: Task 5 ✅
- Optional autostart at logon: Task 5 + Task 6 ✅
- Manager pointing at installed service exe: Task 6 ✅
- End-user docs: Task 7 ✅

**Placeholders:** none.

**Type/name consistency:** `HideAnyWindowService.exe` used consistently. `HideAnyWindowDev` is the cert subject CN. `C:\Program Files\HideAnyWindow\` is the install root throughout. ✅

**Risks called out:**
- WinAppSDK self-contained publish (Task 1) is the most likely place for surprises. If the manager exe doesn't run after publish, debug here before Task 5.
- Ahk2Exe handling of `#Include` paths is generally fine but worth confirming after Task 2.
- `signtool.exe` requires Windows 10 SDK — Task 3 detects and surfaces a clear error if missing.
