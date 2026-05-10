; Default config used when file is missing or unreadable.
GetDefaultConfig() {
    return Map(
        "schemaVersion", 1,
        "serviceState", "running",
        "rules", []
    )
}

GetConfigPath() {
    return GetAppDataDir() "\config.json"
}

; LoadConfig() -> Map
; Returns parsed config or default. Logs malformed reads.
LoadConfig() {
    path := GetConfigPath()
    if !FileExist(path) {
        ServiceLog("INFO", "config.json missing — using defaults")
        return GetDefaultConfig()
    }
    try {
        text := FileRead(path, "UTF-8")
        cfg := JSON.parse(text)
        if !cfg.Has("rules") || !(cfg["rules"] is Array) {
            ServiceLog("WARN", "config.json missing 'rules' array — using defaults")
            return GetDefaultConfig()
        }
        if !cfg.Has("serviceState")
            cfg["serviceState"] := "running"
        if !cfg.Has("schemaVersion")
            cfg["schemaVersion"] := 1
        return cfg
    } catch as e {
        ServiceLog("ERROR", "config.json parse failed: " e.Message)
        return GetDefaultConfig()
    }
}
