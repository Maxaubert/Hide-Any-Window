; ServiceLog(level, msg)
;   level: "INFO" | "WARN" | "ERROR"
;   msg:   string
; Appends one line to %APPDATA%\HideAnyWindow\service.log.

; Ensure the appdata directory exists once at script load (this runs at the
; #Include site, before main.ahk's bootstrap). Done as a script-level
; statement so callers don't have to worry about it.
if !DirExist(A_AppData . "\HideAnyWindow")
    DirCreate(A_AppData . "\HideAnyWindow")

; Returns the appdata directory. Kept for use by test scripts that call it
; from script-level (where AHK doesn't emit the cross-file LocalSameAsGlobal
; warning). Other modules inline the path to avoid that warning.
GetAppDataDir() {
    return A_AppData . "\HideAnyWindow"
}

ServiceLog(level, msg) {
    line := FormatTime(, "yyyy-MM-dd HH:mm:ss") . " | " . level . " | " . msg . "`r`n"
    FileAppend(line, A_AppData . "\HideAnyWindow\service.log")
}
