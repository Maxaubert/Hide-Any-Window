#Requires AutoHotkey v2.0
#Include ..\log.ahk

; Clean slate
logFile := GetAppDataDir() "\service.log"
if FileExist(logFile)
    FileDelete(logFile)

ServiceLog("INFO", "test message 1")
ServiceLog("WARN", "test message 2")
ServiceLog("ERROR", "test message 3")

contents := FileRead(logFile)
assertCount := 0
if InStr(contents, "INFO | test message 1")
    assertCount += 1
if InStr(contents, "WARN | test message 2")
    assertCount += 1
if InStr(contents, "ERROR | test message 3")
    assertCount += 1

if assertCount = 3 {
    MsgBox "log.ahk test PASSED"
    ExitApp 0
} else {
    MsgBox "log.ahk test FAILED — only " assertCount "/3 assertions held`n`nFile contents:`n" contents
    ExitApp 1
}
