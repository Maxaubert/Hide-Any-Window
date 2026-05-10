#Requires AutoHotkey v2.0
#Include ..\lib\JSON.ahk
#Include ..\log.ahk
#Include ..\config.ahk
#Include ..\registry.ahk

if FileExist(GetHiddenJsonPath())
    FileDelete(GetHiddenJsonPath())

results := []

RegistryAdd(111, 0x40000, "magnify-exe", "Magnifier")
RegistryAdd(222, 0x40000, "discord-exe", "Discord")
RegistryAdd(333, 0x40080, "magnify-exe", "Magnifier #2")
results.Push(HiddenEntries.Length = 3 ? "PASS: add 3" : "FAIL: add 3")

removed := RegistryRemoveByRuleId("magnify-exe")
results.Push(removed.Length = 2 && HiddenEntries.Length = 1 && HiddenEntries[1]["hwnd"] = 222
    ? "PASS: remove by ruleId returns 2 and keeps 1"
    : "FAIL: remove by ruleId")

; Confirm hidden.json round-trip
loaded := LoadHiddenJson()
results.Push(loaded.Length = 1 && loaded[1]["hwnd"] = 222
    ? "PASS: hidden.json round-trip"
    : "FAIL: hidden.json round-trip (got " loaded.Length " entries)")

drained := RegistryDrain()
results.Push(drained.Length = 1 && HiddenEntries.Length = 0
    ? "PASS: drain"
    : "FAIL: drain")

allPass := true
report := ""
for r in results {
    report .= r "`n"
    if InStr(r, "FAIL")
        allPass := false
}

MsgBox (allPass ? "registry.ahk PASSED" : "registry.ahk FAILED") "`n`n" report
ExitApp(allPass ? 0 : 1)
