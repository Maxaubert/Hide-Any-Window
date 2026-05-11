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

Write-Host "[1/5] Compiling service via Ahk2Exe..."
$serviceScript = Join-Path $repoRoot 'service\main.ahk'
$serviceExe    = Join-Path $staging 'service\HideAnyWindowService.exe'
Invoke-Ahk2Exe -InScript $serviceScript -OutExe $serviceExe -BaseExe $ahkBaseUia
Write-Host "       -> $serviceExe ($([math]::Round((Get-Item $serviceExe).Length / 1KB))KB)"

$certPfx     = Join-Path $repoRoot 'dist\.cert.pfx'
$certCer     = Join-Path $repoRoot 'dist\installer\HideAnyWindow.cer'
$certSubject = 'CN=HideAnyWindowDev'
$certPwd     = ConvertTo-SecureString 'devpassword' -Force -AsPlainText

if (-not (Test-Path $certPfx)) {
    Write-Host "[2/5] No cert.pfx found - generating self-signed code-signing cert..."
    # Ensure installer dir exists for the .cer export
    $installerDir = Join-Path $repoRoot 'dist\installer'
    if (-not (Test-Path $installerDir)) { New-Item -ItemType Directory -Path $installerDir | Out-Null }

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
    Write-Host "       -> $certCer (public cert, committed)"
} else {
    Write-Host "[2/5] Reusing existing cert.pfx + .cer"
}

Write-Host "[3/5] Signing service exe..."
$signtool = (Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe' -ErrorAction SilentlyContinue |
             Sort-Object FullName -Descending | Select-Object -First 1).FullName
if (-not $signtool) { throw "signtool.exe not found - install Windows 10 SDK (Smart Card / Code Signing tools component) from https://developer.microsoft.com/windows/downloads/windows-sdk/" }

# Strip stale Certificate Table directory entry inherited from the AutoHotkey
# base file. Ahk2Exe appends RCData script resources to the signed AHK base
# without invalidating the IMAGE_DIRECTORY_ENTRY_SECURITY pointer, leaving a
# dangling reference to garbage. signtool then refuses with 0x800700C1
# "bad EXE format". Zeroing the entry restores a clean unsigned PE.
$peBytes = [System.IO.File]::ReadAllBytes($serviceExe)
$peOff = [BitConverter]::ToInt32($peBytes, 0x3C)
$optHdrOff = $peOff + 24
$magic = [BitConverter]::ToUInt16($peBytes, $optHdrOff)
$dataDirOff = if ($magic -eq 0x20B) { $optHdrOff + 112 } else { $optHdrOff + 96 }  # PE32+ vs PE32
$secDirOff = $dataDirOff + (4 * 8)  # IMAGE_DIRECTORY_ENTRY_SECURITY = index 4
for ($i = 0; $i -lt 8; $i++) { $peBytes[$secDirOff + $i] = 0 }
[System.IO.File]::WriteAllBytes($serviceExe, $peBytes)

& $signtool sign /f $certPfx /p 'devpassword' /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $serviceExe
if ($LASTEXITCODE -ne 0) { throw "signtool sign failed with exit $LASTEXITCODE" }
Write-Host "       -> signed: $serviceExe"

Write-Host "[4/5] Publishing manager (self-contained)..."
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
