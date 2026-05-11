# Hide Any Window — installer
# Run from the extracted ZIP folder: right-click -> Run with PowerShell (UAC prompt expected).

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
