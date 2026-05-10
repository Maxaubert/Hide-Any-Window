; ServiceLog(level, msg)
;   level: "INFO" | "WARN" | "ERROR"
;   msg:   string
; Appends one line to %APPDATA%\HideAnyWindow\service.log.
; Creates the directory if needed.

GetAppDataDir() {
    dir := A_AppData "\HideAnyWindow"
    if !DirExist(dir)
        DirCreate(dir)
    return dir
}

ServiceLog(level, msg) {
    line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " level " | " msg "`r`n"
    FileAppend(line, GetAppDataDir() "\service.log")
}
