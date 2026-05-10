#Requires AutoHotkey v2.0
#SingleInstance Force

; ---------------------------------------------------------------------------
; Hide Any Window — Phase A
; Hotkeys:
;   Win+H        Hide the active window
;   Win+Shift+H  Restore the most recently hidden window (LIFO)
; ---------------------------------------------------------------------------

; Stack of hidden windows. Each entry: { hwnd: <UInt>, exStyle: <UInt>, title: <String> }
HiddenStack := []

; Bindings — implementations added in later tasks.
#h::HideActiveWindow()
#+h::RestoreLastWindow()

HideActiveWindow() {
    ; Implemented in Task 2.
}

RestoreLastWindow() {
    ; Implemented in Task 3.
}
