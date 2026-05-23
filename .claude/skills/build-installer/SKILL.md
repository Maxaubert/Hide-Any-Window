---
name: build-installer
description: Use when building, signing, packaging, or debugging the Hide Any Window installer / dist pipeline (dist/build.ps1, the Inno Setup script, code signing, the AHK service exe, or "bad EXE format" / 0xc000027b / Ahk2Exe warning issues). Carries the fragile, hard-to-guess details of the packaging flow.
---

# Building & packaging Hide Any Window

The whole pipeline is `dist\build.ps1` driving four tools in order:
**Ahk2Exe → signtool → `dotnet publish` → Inno Setup (ISCC)**. Run it with:

    powershell -ExecutionPolicy Bypass -File dist\build.ps1

Output: `dist\HideAnyWindow-Setup.exe`. The script sets `$ErrorActionPreference='Stop'`
and checks `$LASTEXITCODE` / output existence after each stage.

## Tool prerequisites (build.ps1 hard-codes these paths and `throw`s if missing)

| Tool | Path it expects |
|---|---|
| Ahk2Exe compiler | `C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe` |
| UIAccess base exe | `C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe` |
| signtool | discovered from the Windows 10/11 SDK |
| Inno Setup 6 | `C:\Program Files (x86)\Inno Setup 6\ISCC.exe` |

If you change machines, these paths are the first thing to check.

## The non-obvious fix-ups in build.ps1 — DO NOT REMOVE

1. **Ahk2Exe warning auto-click.** Compiling against the v2 UIAccess base file raises a
   benign "Base file appears to be invalid" GUI dialog. The script finds that window
   (`*Ahk2Exe Warning*`) and `SendMessage BM_CLICK`s OK. This is why the build is **not
   headless** — it cannot run on a CI agent as-is. (See the audit report for the
   recommended CLI-flag replacement.)
2. **PE Certificate-Table zeroing.** The AHK base file carries a leftover
   `IMAGE_DIRECTORY_ENTRY_SECURITY` entry. If it isn't zeroed before signing, signtool
   fails with `0x800700C1` ("bad EXE format"). The script edits those bytes by hand.
3. **xbf + .pri copy.** WinAppSDK 2.0 *unpackaged* `dotnet publish` drops `*.xbf` and
   `HideAnyWindowManager.pri`. They are copied from `bin\Release` into the publish output;
   without them the manager crashes at launch with `0xc000027b`.

## Code signing & the dev cert

- `build.ps1` generates (or reuses) a self-signed code-signing cert `CN=HideAnyWindowDev`,
  password `devpassword`, exports it to the gitignored `dist\.cert.pfx`, and commits only
  the public `dist\installer\HideAnyWindow.cer`.
- Currently only the **service exe** and the **installer** are signed; the **manager exe is
  not** (a known gap — see the audit report).
- The installer (`HideAnyWindowSetup.iss`) trusts the cert by adding it to the machine
  **Root + TrustedPublisher** stores and removes it on uninstall.
- SECURITY: this is a throwaway dev cert. Never publish a release signed with it. The
  recommended scoped-trust fix (TrustedPublisher only + remove-by-thumbprint) is written up
  in `docs/AUDIT-2026-05.md`.

## Why UIAccess matters here

The service must be UIAccess to manipulate elevated/UIAccess windows (e.g. Magnifier).
UIAccess binaries must be signed AND live in a "secure location" — the installer puts the
service under `{autopf}` (Program Files), which satisfies that. The manager is NOT UIAccess;
it launches the service via ShellExecute. See `CLAUDE.md` for the ShellExecute/740 rule.
