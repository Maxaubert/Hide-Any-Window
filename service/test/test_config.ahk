#Requires AutoHotkey v2.0
#Include ..\lib\JSON.ahk
#Include ..\log.ahk
#Include ..\config.ahk

results := []
testDir := GetAppDataDir()
configPath := GetConfigPath()

; --- Test 1: missing file -> defaults ---
if FileExist(configPath)
    FileDelete(configPath)
cfg := LoadConfig()
results.Push(cfg["serviceState"] = "running" && cfg["rules"].Length = 0
    ? "PASS: missing file -> defaults"
    : "FAIL: missing file -> defaults (got " cfg["serviceState"] ", " cfg["rules"].Length " rules)")

; --- Test 2: malformed file -> defaults ---
FileAppend("not json {{{", configPath)
cfg := LoadConfig()
results.Push(cfg["rules"].Length = 0
    ? "PASS: malformed file -> defaults"
    : "FAIL: malformed file -> defaults")
FileDelete(configPath)

; --- Test 3: valid file -> parsed ---
sample := '{"schemaVersion":1,"serviceState":"stopped","rules":[{"id":"magnify-exe","exe":"magnify.exe","name":"Magnifier","enabled":true}]}'
FileAppend(sample, configPath)
cfg := LoadConfig()
ok := cfg["serviceState"] = "stopped"
    && cfg["rules"].Length = 1
    && cfg["rules"][1]["exe"] = "magnify.exe"
    && cfg["rules"][1]["enabled"] = true
results.Push(ok ? "PASS: valid file -> parsed" : "FAIL: valid file -> parsed")
FileDelete(configPath)

allPass := true
report := ""
for r in results {
    report .= r "`n"
    if InStr(r, "FAIL")
        allPass := false
}

if allPass {
    MsgBox "config.ahk tests PASSED`n`n" report
    ExitApp 0
} else {
    MsgBox "config.ahk tests FAILED`n`n" report
    ExitApp 1
}
