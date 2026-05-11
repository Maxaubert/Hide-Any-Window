; Hide Any Window — Inno Setup script
; Compiled by dist\build.ps1 (calls ISCC.exe)

#define MyAppName     "Hide Any Window"
#define MyAppVersion  "0.1.0"
#define MyAppPublisher "HideAnyWindowDev"
#define MyAppExeName  "HideAnyWindowManager.exe"
#define MyServiceExe  "HideAnyWindowService.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-1234567890AB}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\HideAnyWindow
DisableProgramGroupPage=yes
DisableDirPage=auto
OutputBaseFilename=HideAnyWindow-Setup
OutputDir={#SourcePath}\..
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
SetupIconFile={#SourcePath}\..\icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "autostart"; Description: "Start the service automatically when I sign in to Windows"; GroupDescription: "Optional:"

[Files]
; Self-contained manager (.NET + WinAppSDK runtime + the manager exe + DLLs)
Source: "{#SourcePath}\..\staging\manager\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Compiled service exe
Source: "{#SourcePath}\..\staging\service\{#MyServiceExe}"; DestDir: "{app}"; Flags: ignoreversion
; Public cert (used by [Run] then deleted after install)
Source: "{#SourcePath}\HideAnyWindow.cer"; DestDir: "{app}"; Flags: ignoreversion deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
; 1. Trust the bundled code-signing cert (system-wide) — required so the
;    UIAccess service exe can elevate without a UAC prompt at runtime.
Filename: "certutil.exe"; Parameters: "-addstore Root ""{app}\HideAnyWindow.cer"""; \
    StatusMsg: "Trusting the code-signing certificate..."; Flags: runhidden waituntilterminated

Filename: "certutil.exe"; Parameters: "-addstore TrustedPublisher ""{app}\HideAnyWindow.cer"""; \
    StatusMsg: "Adding to Trusted Publishers..."; Flags: runhidden waituntilterminated

; 2. (Optional) create at-logon scheduled task — only if the user ticked the box.
Filename: "schtasks.exe"; Parameters: "/Create /TN ""HideAnyWindowService"" /SC ONLOGON /RL HIGHEST /TR ""\""{app}\{#MyServiceExe}\"""" /F"; \
    StatusMsg: "Creating logon task..."; Flags: runhidden waituntilterminated; Tasks: autostart

; 3. Optional: offer to launch the manager when install finishes.
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; \
    Flags: nowait postinstall skipifsilent runascurrentuser

[UninstallRun]
; Best-effort cleanup. RunOnceId stops Inno from running twice on repeated uninstall.
Filename: "schtasks.exe"; Parameters: "/Delete /TN ""HideAnyWindowService"" /F"; \
    Flags: runhidden waituntilterminated; RunOnceId: "RemoveTask"
Filename: "certutil.exe"; Parameters: "-delstore Root ""HideAnyWindowDev"""; \
    Flags: runhidden waituntilterminated; RunOnceId: "RemoveCertRoot"
Filename: "certutil.exe"; Parameters: "-delstore TrustedPublisher ""HideAnyWindowDev"""; \
    Flags: runhidden waituntilterminated; RunOnceId: "RemoveCertPublisher"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
