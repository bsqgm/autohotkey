#Requires AutoHotkey v2.0
SetCapsLockState "AlwaysOff"

; --- 全局配置 ---
AppIDCache := Map()

; --- 初始化：批量缓存所有需要的应用 AppID ---
InitAppCache() {
    global AppIDCache
    try {
        shell := ComObject("WScript.Shell")
         exec := shell.Exec("powershell -NoProfile -Command `"Get-StartApps | ForEach-Object { $_.Name + '|' + $_.AppID }`"")
        output := exec.StdOut.ReadAll()
        for line in StrSplit(output, "`n", "`r") {
            parts := StrSplit(line, "|",, 2)
            if parts.Length = 2 && Trim(parts[2]) != ""
                AppIDCache[Trim(parts[1])] := Trim(parts[2])
        }
    }
}
InitAppCache()

; --- 核心工具函数：移动窗口到鼠标所在屏幕并居中 ---
AlignWindowToMouse(hwnd) {
    if !hwnd
        return

    WinShow(hwnd)
    if DllCall("IsIconic", "Ptr", hwnd)
        WinRestore(hwnd)

    ; 等待窗口恢复完成，确保尺寸正确
    Sleep 50
    WinActivate(hwnd)
    WinWaitActive("ahk_id " hwnd,, 1)

    MouseGetPos(&mX, &mY)

    ; 用 Buffer 正确打包 POINT，避免负坐标位运算问题
    pt := Buffer(8)
    NumPut("Int", mX, pt, 0)
    NumPut("Int", mY, pt, 4)
    hMonitor := DllCall("MonitorFromPoint", "Int64", NumGet(pt, 0, "Int64"), "UInt", 2, "Ptr")

    NumPut("UInt", 40, mi := Buffer(40))
    if DllCall("GetMonitorInfo", "Ptr", hMonitor, "Ptr", mi) {
        waLeft   := NumGet(mi, 20, "Int")
        waTop    := NumGet(mi, 24, "Int")
        waRight  := NumGet(mi, 28, "Int")
        waBottom := NumGet(mi, 32, "Int")
        waWidth  := waRight - waLeft
        waHeight := waBottom - waTop

        WinGetPos(,, &wW, &wH, hwnd)

        targetX := waLeft + (waWidth - wW) // 2
        targetY := waTop + (waHeight - wH) // 2

        WinMove(targetX, targetY,,, hwnd)
    }
}

; --- 统一切换函数 ---
ToggleApp(exeName, appName := "") {
    global AppIDCache

    ; 窗口已存在 → 移到鼠标屏幕
    if (hwnd := WinExist("ahk_exe " exeName)) {
        AlignWindowToMouse(hwnd)
        return
    }

    ; 窗口不存在 → 启动应用
    ; 优先通过 AppID 启动（覆盖传统应用和 UWP）
    if (appName != "" && AppIDCache.Has(appName)) {
        Run "explorer.exe shell:AppsFolder\" . AppIDCache[appName]
        return
    }

    ; Fallback：直接 Run exe 名
    try {
        Run exeName
    }
}

; --- 热键绑定（exeName 用于匹配窗口，appName 用于启动）---
CapsLock & f:: ToggleApp("OneCommander.exe",      "OneCommander")
CapsLock & a:: ToggleApp("tabby.exe",             "Tabby Terminal")
CapsLock & e:: ToggleApp("notepad++.exe",         "Notepad++")
CapsLock & s:: ToggleApp("chrome.exe",            "Google Chrome")
CapsLock & x:: ToggleApp("Cherry Studio.exe",     "Cherry Studio")
CapsLock & g:: ToggleApp("clash-verge.exe",       "Clash Verge")
CapsLock & w:: ToggleApp("Notion.exe",            "Notion")
CapsLock & c:: ToggleApp("devenv.exe",            "Visual Studio 2022")
