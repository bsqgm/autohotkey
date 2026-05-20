#Requires AutoHotkey v2.0
SetCapsLockState "AlwaysOff"

if !A_IsAdmin {
    try Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    ExitApp
}

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

; --- 将当前焦点窗口移动到另一个屏幕 ---
MoveActiveWindowToNextMonitor() {
    hwnd := WinExist("A")
    if !hwnd
        return

    ; 避免误操作桌面、任务栏等特殊窗口
    try {
        cls := WinGetClass("ahk_id " hwnd)
        if (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd")
            return
    }

    monitorCount := MonitorGetCount()
    if (monitorCount < 2)
        return

    winState := WinGetMinMax("ahk_id " hwnd)
    wasMaximized := (winState = 1)

    ; 最大化窗口需要先还原，否则 WinMove 可能无效或位置不准确
    if (winState != 0) {
        WinRestore("ahk_id " hwnd)
        Sleep 80
    }

    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)

    currentMonitor := GetMonitorIndexFromWindowRect(x, y, w, h)
    targetMonitor := (currentMonitor = monitorCount) ? 1 : currentMonitor + 1

    MonitorGetWorkArea(targetMonitor, &waLeft, &waTop, &waRight, &waBottom)

    waWidth := waRight - waLeft
    waHeight := waBottom - waTop

    ; 如果窗口比目标屏幕工作区大，就缩小到工作区大小
    newW := Min(w, waWidth)
    newH := Min(h, waHeight)

    ; 移动到目标屏幕并居中
    targetX := waLeft + (waWidth - newW) // 2
    targetY := waTop + (waHeight - newH) // 2

    WinMove(targetX, targetY, newW, newH, "ahk_id " hwnd)

    ; 如果原本是最大化状态，移动后重新最大化
    if wasMaximized
        WinMaximize("ahk_id " hwnd)

    WinActivate("ahk_id " hwnd)
}

; --- 根据窗口矩形判断它当前主要位于哪个屏幕 ---
GetMonitorIndexFromWindowRect(x, y, w, h) {
    monitorCount := MonitorGetCount()

    bestMonitor := 1
    bestArea := -1

    Loop monitorCount {
        MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)

        overlapW := Max(0, Min(x + w, mRight) - Max(x, mLeft))
        overlapH := Max(0, Min(y + h, mBottom) - Max(y, mTop))
        overlapArea := overlapW * overlapH

        if (overlapArea > bestArea) {
            bestArea := overlapArea
            bestMonitor := A_Index
        }
    }

    return bestMonitor
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

; --- 专门切换 / 启动 Visual Studio ---
ToggleVS() {
    global AppIDCache

    ; 1. 如果 VS 已经打开，移动到鼠标所在屏幕并激活
    if (hwnd := FindMainWindowByExe("devenv.exe")) {
        AlignWindowToMouse(hwnd)
        return
    }

    ; 2. 优先通过 StartApps 启动
    vsNames := ["Visual Studio 2022", "Visual Studio 2022 Preview", "Visual Studio 2019"]

    for _, name in vsNames {
        if AppIDCache.Has(name) {
            Run "explorer.exe shell:AppsFolder\" . AppIDCache[name]
            return
        }
    }

    ; 3. 再通过 vswhere.exe 找 devenv.exe
    if (devenv := GetVSDevenvPath()) {
        q := Chr(34)
        Run q devenv q
        return
    }

    MsgBox "没有找到 Visual Studio。请确认 StartApps 里的名称，或者手动填 devenv.exe 的完整路径。"
}

; --- 找指定 exe 的可见主窗口 ---
FindMainWindowByExe(exeName) {
    for hwnd in WinGetList("ahk_exe " exeName) {
        try {
            title := WinGetTitle("ahk_id " hwnd)
            style := WinGetStyle("ahk_id " hwnd)
            exStyle := WinGetExStyle("ahk_id " hwnd)
        } catch {
            continue
        }

        ; 跳过无标题窗口
        if (title = "")
            continue

        ; WS_VISIBLE = 0x10000000
        if !((style & 0x10000000))
            continue

        ; WS_EX_TOOLWINDOW = 0x80，跳过工具窗口
        if (exStyle & 0x80)
            continue

        return hwnd
    }

    return 0
}

; --- 用 vswhere.exe 自动寻找 Visual Studio 的 devenv.exe ---
GetVSDevenvPath() {
    pf86 := EnvGet("ProgramFiles(x86)")
    if (pf86 = "")
        pf86 := EnvGet("ProgramFiles")

    vswhere := pf86 "\Microsoft Visual Studio\Installer\vswhere.exe"
    if !FileExist(vswhere)
        return ""

    q := Chr(34)

    try {
        shell := ComObject("WScript.Shell")
        cmd := q vswhere q " -latest -products * -requires Microsoft.VisualStudio.Component.CoreEditor -property installationPath"
        exec := shell.Exec(cmd)
        installPath := Trim(exec.StdOut.ReadAll())
    } catch {
        return ""
    }

    if (installPath = "")
        return ""

    devenv := installPath "\Common7\IDE\devenv.exe"
    return FileExist(devenv) ? devenv : ""
}

; --- 通过 OneCommander 打开指定目录 ---
OpenFolder(folderPath) {
    if !DirExist(folderPath) {
        MsgBox "目录不存在：`n" folderPath
        return
    }

    ocExe := GetOneCommanderExe()
    q := Chr(34)

    ; 方案 A：直接打开到指定目录
    ; Run q . ocExe . q . " " . q . folderPath . q

    ; 方案 B：在 OneCommander 新标签页打开指定目录
    try {
        Run q . ocExe . q . " -o " . q . folderPath . q . " -newtab"
    } catch Error as e {
        MsgBox "无法启动 OneCommander。`n`n请检查 OneCommander.exe 路径是否正确。`n`n当前尝试路径：`n" ocExe
    }
}

; --- 自动寻找 OneCommander.exe ---
GetOneCommanderExe() {
    ; 如果 OneCommander 已经在运行，优先使用它的真实 exe 路径
    try {
        path := WinGetProcessPath("ahk_exe OneCommander.exe")
        if (path != "" && FileExist(path))
            return path
    }

    ; 常见安装位置
    candidates := [
        EnvGet("LOCALAPPDATA") "\Programs\OneCommander\OneCommander.exe",
        EnvGet("LOCALAPPDATA") "\Microsoft\WindowsApps\OneCommander.exe",
        EnvGet("ProgramFiles") "\OneCommander\OneCommander.exe",
        EnvGet("ProgramFiles(x86)") "\OneCommander\OneCommander.exe"
    ]

    for path in candidates {
        if (path != "" && FileExist(path))
            return path
    }

    ; 最后兜底：如果 OneCommander.exe 已经在 PATH / App Execution Alias 里，这个也可能成功
    return "OneCommander.exe"
}

; --- 热键绑定（exeName 用于匹配窗口，appName 用于启动）---
CapsLock & f:: ToggleApp("OneCommander.exe",      "OneCommander")
CapsLock & a:: ToggleApp("tabby.exe",             "Tabby Terminal")
CapsLock & e:: ToggleApp("notepad++.exe",         "Notepad++")
CapsLock & s:: ToggleApp("chrome.exe",            "Google Chrome")
CapsLock & x:: ToggleApp("Cherry Studio.exe",     "Cherry Studio")
CapsLock & g:: ToggleApp("clash party.exe",       "Clash Party")
CapsLock & w:: ToggleApp("Notion.exe",            "Notion")
CapsLock & c:: ToggleApp("codex.exe",             "Codex")
CapsLock & v:: ToggleVS()
CapsLock & b:: MoveActiveWindowToNextMonitor()
CapsLock & 1:: OpenFolder("d:\Downloads")

CapsLock & F12:: {
    global AppIDCache

    text := ""
    for name, appid in AppIDCache {
        if InStr(name, "Visual Studio")
            text .= name " | " appid "`n"
    }

    MsgBox text = "" ? "AppIDCache 里没找到 Visual Studio" : text
}
