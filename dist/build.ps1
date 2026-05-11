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

# --- Helper: run Ahk2Exe and auto-dismiss the benign "Base file appears to
# be invalid" warning that Ahk2Exe v1.1.37 raises against AHK v2 base files.
# Pressing OK on this dialog produces a fully working exe; this is a known
# heuristic mismatch, not a real error. Any other dialog (e.g. "Ahk2Exe
# Error") is treated as a hard failure.
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Ahk2ExeWin32 {
    [DllImport("user32.dll")]
    public static extern IntPtr FindWindowEx(IntPtr p, IntPtr c, string cl, string w);
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@

function Invoke-Ahk2Exe {
    param(
        [Parameter(Mandatory)] [string] $InScript,
        [Parameter(Mandatory)] [string] $OutExe,
        [Parameter(Mandatory)] [string] $BaseExe
    )
    $proc = Start-Process -FilePath $ahk2Exe `
        -ArgumentList "/in", "`"$InScript`"", "/out", "`"$OutExe`"", "/base", "`"$BaseExe`"" `
        -PassThru
    # Poll for dialog up to 30s; compile usually finishes in < 5s once warning
    # is dismissed.
    for ($i = 0; $i -lt 60; $i++) {
        if ($proc.HasExited) { break }
        Start-Sleep -Milliseconds 500
        $proc.Refresh()
        if ($proc.MainWindowTitle -like "*Ahk2Exe Warning*") {
            $btn = [Ahk2ExeWin32]::FindWindowEx($proc.MainWindowHandle, [IntPtr]::Zero, "Button", "OK")
            if ($btn -ne [IntPtr]::Zero) {
                # BM_CLICK = 0x00F5
                [Ahk2ExeWin32]::SendMessage($btn, 0xF5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
            }
        } elseif ($proc.MainWindowTitle -like "*Ahk2Exe Error*") {
            $proc | Stop-Process -Force
            throw "Ahk2Exe error dialog appeared while compiling $InScript (see Ahk2Exe.exe interactively for details)"
        }
    }
    if (-not $proc.WaitForExit(60000)) {
        $proc | Stop-Process -Force
        throw "Ahk2Exe timed out compiling $InScript"
    }
    if ($proc.ExitCode -ne 0) {
        throw "Ahk2Exe exited with code $($proc.ExitCode) compiling $InScript"
    }
    if (-not (Test-Path $OutExe)) {
        throw "Ahk2Exe produced no output at $OutExe"
    }
}

Write-Host "[1/4] Compiling service via Ahk2Exe..."
$serviceScript = Join-Path $repoRoot 'service\main.ahk'
$serviceExe    = Join-Path $staging 'service\HideAnyWindowService.exe'
Invoke-Ahk2Exe -InScript $serviceScript -OutExe $serviceExe -BaseExe $ahkBaseUia
Write-Host "       -> $serviceExe ($([math]::Round((Get-Item $serviceExe).Length / 1KB))KB)"

Write-Host "Done so far. Subsequent steps land in later tasks."
