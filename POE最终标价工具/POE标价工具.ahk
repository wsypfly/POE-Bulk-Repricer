#SingleInstance Force
#NoEnv
#Persistent
#InstallKeybdHook
#UseHook
DllCall("SetProcessDPIAware")
SendMode Input
SetBatchLines, -1
CoordMode, Pixel, Screen
CoordMode, Mouse, Screen

global AppDir := A_ScriptDir
global SettingsPath := AppDir . "\settings.ini"
global GameWindowTitle := "流放之路"
global GameWindowSpec := "ahk_class POEWindowClass ahk_exe PathOfExile_x64.exe"

global BorderColor := "E7B477"
global CenterColor := "070707"
global PriceMode := "Discount"
global PriceValue := "8"
global RoundingMode := "Round"
global BatchHotkey := "F3"
global PreviewHotkey := "F4"
global RegisteredBatchHotkey := ""
global RegisteredPreviewHotkey := ""
global DebugMode := 0

LoadSettings()
EnsureSettingsFile()
BuildMainGui()
err := RegisterHotkeys()
if (err != "")
    MsgBox, 48, 热键注册失败, %err%
SetStatus("已就绪。批量改价：" . BatchHotkey . "；检测预览：" . PreviewHotkey)
Return

BatchHotkeyLabel:
    RunBatchPrice()
Return

PreviewHotkeyLabel:
    RunPreview()
Return

SaveSettingsButton:
    SaveSettingsFromGui()
Return

RunPreviewButton:
    RunPreview()
Return

RunBatchButton:
    RunBatchPrice()
Return

ShowHelpButton:
    ShowHelpWindow()
Return

MainGuiClose:
MainGuiEscape:
    ExitApp
Return

LoadSettings() {
    global SettingsPath, BorderColor, CenterColor, PriceMode, PriceValue, RoundingMode, BatchHotkey, PreviewHotkey, DebugMode

    IniRead, DebugMode, %SettingsPath%, General, DebugMode, 0
    IniRead, BorderColor, %SettingsPath%, Detection, BorderColor, E7B477
    IniRead, CenterColor, %SettingsPath%, Detection, CenterColor, 070707
    IniRead, PriceMode, %SettingsPath%, Pricing, Mode, Discount
    IniRead, PriceValue, %SettingsPath%, Pricing, Value, 8
    IniRead, RoundingMode, %SettingsPath%, Pricing, Rounding, Round
    IniRead, BatchHotkey, %SettingsPath%, Hotkeys, Batch, F3
    IniRead, PreviewHotkey, %SettingsPath%, Hotkeys, Preview, F4

    BorderColor := NormalizeHex(BorderColor, "E7B477")
    CenterColor := NormalizeHex(CenterColor, "070707")
    PriceMode := (PriceMode = "Adjust") ? "Adjust" : "Discount"
    RoundingMode := NormalizeRounding(RoundingMode)
    BatchHotkey := Trim(BatchHotkey)
    PreviewHotkey := Trim(PreviewHotkey)
    if (BatchHotkey = "")
        BatchHotkey := "F3"
    if (PreviewHotkey = "")
        PreviewHotkey := "F4"
    DebugMode := (DebugMode = 1) ? 1 : 0
}

EnsureSettingsFile() {
    global SettingsPath
    if (!FileExist(SettingsPath))
        WriteSettings()
}

WriteSettings() {
    global SettingsPath, BorderColor, CenterColor, PriceMode, PriceValue, RoundingMode, BatchHotkey, PreviewHotkey, DebugMode
    IniWrite, %DebugMode%, %SettingsPath%, General, DebugMode
    IniWrite, %BorderColor%, %SettingsPath%, Detection, BorderColor
    IniWrite, %CenterColor%, %SettingsPath%, Detection, CenterColor
    IniWrite, %PriceMode%, %SettingsPath%, Pricing, Mode
    IniWrite, %PriceValue%, %SettingsPath%, Pricing, Value
    IniWrite, %RoundingMode%, %SettingsPath%, Pricing, Rounding
    IniWrite, %BatchHotkey%, %SettingsPath%, Hotkeys, Batch
    IniWrite, %PreviewHotkey%, %SettingsPath%, Hotkeys, Preview
}

BuildMainGui() {
    global BorderColor, CenterColor, PriceMode, PriceValue, RoundingMode, BatchHotkey, PreviewHotkey, DebugMode
    global GuiBorderColor, GuiCenterColor, GuiPriceMode, GuiPriceValue, GuiRoundingMode, GuiBatchHotkey, GuiPreviewHotkey, GuiDebugMode, StatusText

    modeChoices := (PriceMode = "Adjust") ? "打折|统一加减||" : "打折||统一加减"
    roundingChoices := "四舍五入||向下取整|向上取整"
    if (RoundingMode = "Floor")
        roundingChoices := "四舍五入|向下取整||向上取整"
    else if (RoundingMode = "Ceil")
        roundingChoices := "四舍五入|向下取整|向上取整||"

    Gui, Main:New, +HwndMainHwnd, POE标价工具
    Gui, Main:Font, s10, Microsoft YaHei
    Gui, Main:Margin, 14, 12

    Gui, Main:Add, GroupBox, xm ym w450 h138, 识别设置
    Gui, Main:Add, Text, xp+16 yp+30 w90 h24, 边框颜色
    Gui, Main:Add, Edit, x+8 yp-2 w120 vGuiBorderColor, %BorderColor%
    Gui, Main:Add, Text, x+18 yp+2 w190 h22, 6位RGB，例如 E7B477
    Gui, Main:Add, Text, xm+16 y+16 w90 h24, 中心颜色
    Gui, Main:Add, Edit, x+8 yp-2 w120 vGuiCenterColor, %CenterColor%
    Gui, Main:Add, Text, x+18 yp+2 w190 h22, 空格中心色，例如 070707

    Gui, Main:Add, GroupBox, xm y+24 w450 h170, 改价规则
    Gui, Main:Add, Text, xp+16 yp+30 w90 h24, 改价模式
    Gui, Main:Add, DropDownList, x+8 yp-4 w132 vGuiPriceMode, %modeChoices%
    Gui, Main:Add, Text, x+18 yp+4 w180 h22, 打折或统一加减
    Gui, Main:Add, Text, xm+16 y+18 w90 h24, 改价值
    Gui, Main:Add, Edit, x+8 yp-2 w132 vGuiPriceValue, %PriceValue%
    Gui, Main:Add, Text, x+18 yp+2 w190 h22, 打折填 8；加减填 -5 或 +5
    Gui, Main:Add, Text, xm+16 y+18 w90 h24, 取整方式
    Gui, Main:Add, DropDownList, x+8 yp-4 w132 vGuiRoundingMode, %roundingChoices%

    Gui, Main:Add, GroupBox, xm y+24 w450 h134, 热键
    Gui, Main:Add, Text, xp+16 yp+30 w90 h24, 批量改价
    Gui, Main:Add, Edit, x+8 yp-2 w132 vGuiBatchHotkey, %BatchHotkey%
    Gui, Main:Add, Text, x+18 yp+2 w190 h22, 默认 F3
    Gui, Main:Add, Text, xm+16 y+16 w90 h24, 检测预览
    Gui, Main:Add, Edit, x+8 yp-2 w132 vGuiPreviewHotkey, %PreviewHotkey%
    Gui, Main:Add, Text, x+18 yp+2 w190 h22, 默认 F4

    Gui, Main:Add, Checkbox, xm y+18 w180 vGuiDebugMode Checked%DebugMode%, 调试模式（保留日志/截图）
    Gui, Main:Add, Button, xm y+14 w96 h32 gSaveSettingsButton Default, 保存设置
    Gui, Main:Add, Button, x+8 w112 h32 gRunPreviewButton, 检测预览
    Gui, Main:Add, Button, x+8 w112 h32 gRunBatchButton, 批量改价
    Gui, Main:Add, Button, x+8 w96 h32 gShowHelpButton, 使用说明
    Gui, Main:Add, Text, xm y+12 w450 h42 vStatusText, 
    Gui, Main:Show, w480, POE标价工具
    GuiControl, Focus, 保存设置
}

SaveSettingsFromGui() {
    global BorderColor, CenterColor, PriceMode, PriceValue, RoundingMode, BatchHotkey, PreviewHotkey, DebugMode
    global GuiBorderColor, GuiCenterColor, GuiPriceMode, GuiPriceValue, GuiRoundingMode, GuiBatchHotkey, GuiPreviewHotkey, GuiDebugMode

    Gui, Main:Submit, NoHide
    newBorderColor := NormalizeHex(GuiBorderColor, "")
    newCenterColor := NormalizeHex(GuiCenterColor, "")
    if (newBorderColor = "" || newCenterColor = "") {
        MsgBox, 48, 设置错误, 颜色必须是 6 位十六进制，例如 E7B477。
        return false
    }

    newValue := Trim(GuiPriceValue)
    if (!IsNumberText(newValue)) {
        MsgBox, 48, 设置错误, 改价值必须是数字，例如 8、8.5、-5、+5。
        return false
    }

    newBatchHotkey := Trim(GuiBatchHotkey)
    newPreviewHotkey := Trim(GuiPreviewHotkey)
    if (newBatchHotkey = "" || newPreviewHotkey = "") {
        MsgBox, 48, 设置错误, 热键不能为空。
        return false
    }
    if (newBatchHotkey = newPreviewHotkey) {
        MsgBox, 48, 设置错误, 批量改价热键和检测预览热键不能相同。
        return false
    }

    newMode := (GuiPriceMode = "统一加减") ? "Adjust" : "Discount"
    newRounding := RoundingTextToMode(GuiRoundingMode)
    if (!ConfirmDangerousSettings(newMode, newValue))
        return false

    oldBatch := BatchHotkey
    oldPreview := PreviewHotkey
    BorderColor := newBorderColor
    CenterColor := newCenterColor
    PriceMode := newMode
    PriceValue := newValue
    RoundingMode := newRounding
    BatchHotkey := newBatchHotkey
    PreviewHotkey := newPreviewHotkey
    DebugMode := GuiDebugMode ? 1 : 0

    err := RegisterHotkeys()
    if (err != "") {
        BatchHotkey := oldBatch
        PreviewHotkey := oldPreview
        RegisterHotkeys()
        MsgBox, 48, 热键注册失败, %err%
        return false
    }

    WriteSettings()
    SetStatus("设置已保存并生效。批量改价：" . BatchHotkey . "；检测预览：" . PreviewHotkey)
    return true
}

RegisterHotkeys() {
    global BatchHotkey, PreviewHotkey, RegisteredBatchHotkey, RegisteredPreviewHotkey

    if (RegisteredBatchHotkey != "") {
        Hotkey, %RegisteredBatchHotkey%, Off, UseErrorLevel
        RegisteredBatchHotkey := ""
    }
    if (RegisteredPreviewHotkey != "") {
        Hotkey, %RegisteredPreviewHotkey%, Off, UseErrorLevel
        RegisteredPreviewHotkey := ""
    }

    Hotkey, %BatchHotkey%, BatchHotkeyLabel, UseErrorLevel On
    if ErrorLevel
        return "批量改价热键无效：" . BatchHotkey
    RegisteredBatchHotkey := BatchHotkey

    Hotkey, %PreviewHotkey%, PreviewHotkeyLabel, UseErrorLevel On
    if ErrorLevel {
        Hotkey, %RegisteredBatchHotkey%, Off, UseErrorLevel
        RegisteredBatchHotkey := ""
        return "检测预览热键无效：" . PreviewHotkey
    }
    RegisteredPreviewHotkey := PreviewHotkey
    return ""
}

RunPreview() {
    ActivateGameWindow()
    items := FindHighlightedItemsByScreenshot()
    text := "识别到 " . items.Length() . " 个物品：`n"
    for index, item in items
        text .= index . ": " . item.range . " " . item.w . "x" . item.h . " @ screen(" . item.sx . ", " . item.sy . ")`n"
    Clipboard := text
    SetStatus("检测完成：识别到 " . items.Length() . " 个物品，结果已复制到剪贴板。")
    MsgBox, 64, 检测预览, % text . "`n结果已复制到剪贴板。"
}

RunBatchPrice() {
    global AppDir, PriceMode, PriceValue, RoundingMode, DebugMode

    if (!ConfirmDangerousSettings(PriceMode, PriceValue))
        return

    if (!ActivateGameWindow()) {
        SetStatus("没有找到流放之路窗口。")
        return
    }
    SetStatus("正在搜索物品并识别高亮边框...")
    SearchText := Chr(0x7269) . Chr(0x54C1)
    OldClip := ClipboardAll
    Clipboard := SearchText
    SendInput, ^f
    Sleep, 120
    SendInput, ^a
    SendInput, ^v
    Sleep, 120
    SendInput, {Enter}
    Sleep, 1000

    items := FindHighlightedItemsByScreenshot()
    count := items.Length()
    if (count < 1) {
        Clipboard := OldClip
        OldClip := ""
        SetStatus("没有识别到物品。")
        return
    }

    csvPath := ""
    if (DebugMode) {
        FormatTime, stamp,, yyyyMMdd_HHmmss
        csvPath := AppDir . "\market_discount_log_" . stamp . ".csv"
        header := CsvLine("index", "grid_range", "center_x", "center_y", "screen_x", "screen_y", "raw_clipboard", "original", "new_price", "mode", "value", "rounding", "status", "error")
        FileAppend, % header . "`r`n", %csvPath%, UTF-8
    }

    okCount := 0
    failText := ""

    Loop, %count% {
        index := A_Index
        item := items[index]
        SetStatus("批量改价中：" . index . "/" . count . " " . item.range)
        row := AdjustPriceAt(item.sx, item.sy)
        if (DebugMode)
            FileAppend, % CsvLine(index, item.range, item.cx, item.cy, item.sx, item.sy, row.raw, row.original, row.newPrice, PriceMode, PriceValue, RoundingMode, row.status, row.err) . "`r`n", %csvPath%, UTF-8

        if (row.ok) {
            okCount++
        } else {
            failText .= "第 " . index . " 个 " . item.range . " 失败：" . row.err . "`n"
        }
        Sleep, 180
    }

    Clipboard := OldClip
    OldClip := ""

    if (DebugMode && failText != "")
        SetStatus("批量改价完成：" . okCount . "/" . count . "，有失败项，详见日志。")
    else
        SetStatus("批量改价完成：" . okCount . "/" . count)
}

AdjustPriceAt(x, y) {
    row := {}
    row.ok := false
    row.raw := ""
    row.original := ""
    row.newPrice := ""
    row.status := "failed"
    row.err := ""

    Clipboard := ""
    MouseMove, %x%, %y%, 0
    Sleep, 80
    Click, right
    Sleep, 120
    SendInput, ^c
    ClipWait, 1

    if ErrorLevel {
        SendInput, {Esc}
        row.err := "无法复制价格"
        return row
    }

    row.raw := Clipboard
    numText := Trim(Clipboard)
    normalizedText := StrReplace(numText, ",")
    if (!RegExMatch(normalizedText, "[-+]?\d+(\.\d+)?", match)) {
        SendInput, {Esc}
        row.err := "剪贴板内容不是有效数字：" . numText
        return row
    }

    original := match + 0
    calc := ComputeNewPrice(original)
    row.original := original
    row.newPrice := calc.price
    row.status := calc.status

    SendInput, % calc.price
    Sleep, 50
    SendInput, {Enter}
    row.ok := true
    row.err := ""
    return row
}

ComputeNewPrice(original) {
    global PriceMode, PriceValue, RoundingMode

    value := PriceValue + 0
    if (PriceMode = "Adjust")
        raw := original + value
    else
        raw := original * (value / 10.0)

    if (RoundingMode = "Floor")
        price := Floor(raw)
    else if (RoundingMode = "Ceil")
        price := Ceil(raw)
    else
        price := Round(raw)

    status := "ok"
    if (price < 1) {
        price := 1
        status := "clamped_to_1"
    }

    result := {}
    result.price := price
    result.status := status
    return result
}

FindHighlightedItemsByScreenshot() {
    global AppDir, DebugMode

    if (DebugMode) {
        outPath := AppDir . "\market_detect_items.tsv"
        debugPath := AppDir . "\market_discount_debug.txt"
    } else {
        outPath := A_Temp . "\poe_market_detect_items_" . A_TickCount . ".tsv"
        debugPath := A_Temp . "\poe_market_discount_debug_" . A_TickCount . ".txt"
    }
    detectorExe := AppDir . "\market_detect_items.exe"
    detectorPy := AppDir . "\market_detect_items.py"

    FileDelete, %outPath%
    FileDelete, %debugPath%

    if (FileExist(detectorExe)) {
        cmd := QuoteArg(detectorExe) . " " . QuoteArg(outPath) . " " . QuoteArg(debugPath)
    } else if (FileExist(detectorPy)) {
        cmd := A_ComSpec . " /c python " . QuoteArg(detectorPy) . " " . QuoteArg(outPath) . " " . QuoteArg(debugPath)
    } else {
        SetStatus("检测器缺失。")
        return []
    }

    RunWait, %cmd%, %AppDir%, Hide
    exitCode := ErrorLevel
    items := []
    if (exitCode != 0 || !FileExist(outPath)) {
        SetStatus("检测器运行失败，Exit code: " . exitCode)
        return items
    }

    Loop, Read, %outPath%
    {
        if (A_Index = 1)
            continue
        line := A_LoopReadLine
        if (line = "")
            continue
        fields := StrSplit(line, A_Tab)
        if (fields.Length() < 9)
            continue

        item := {}
        item.c := fields[2] + 0
        item.r := fields[3] + 0
        item.w := fields[4] + 0
        item.h := fields[5] + 0
        item.range := fields[6]
        item.cells := fields[7]
        item.cx := fields[8] + 0
        item.cy := fields[9] + 0
        item.sx := (fields.Length() >= 15) ? fields[14] + 0 : item.cx
        item.sy := (fields.Length() >= 15) ? fields[15] + 0 : item.cy
        items.Push(item)
    }

    if (!DebugMode) {
        FileDelete, %outPath%
        FileDelete, %debugPath%
    }
    return items
}

ActivateGameWindow() {
    global GameWindowTitle, GameWindowSpec

    if WinExist(GameWindowSpec) {
        WinActivate
        WinWaitActive, %GameWindowSpec%,, 1
        Sleep, 120
        return true
    } else if WinExist(GameWindowTitle) {
        WinActivate
        WinWaitActive, %GameWindowTitle%,, 1
        Sleep, 120
        return true
    }
    return false
}

ConfirmDangerousSettings(mode, valueText) {
    value := valueText + 0
    if (mode = "Discount") {
        if (value < 1) {
            MsgBox, 52, 强烈确认, % "当前折扣是 " . valueText . " 折，价格会极低。请核实是否继续？"
            IfMsgBox, No
                return false
        } else if (value < 5) {
            MsgBox, 52, 二次确认, % "当前折扣小于 5 折：" . valueText . " 折。是否继续？"
            IfMsgBox, No
                return false
        }
    } else if (mode = "Adjust" && value < 0) {
        MsgBox, 52, 减价确认, % "当前为统一减价：" . valueText . "。低于 1 的价格会按 1 标价。是否继续？"
        IfMsgBox, No
            return false
    }
    return true
}

ShowHelpWindow() {
    help =
    (LTrim
    使用步骤
    1. 打开流放之路，并进入要改价的仓库页。
    2. 先点“检测预览”或按预览热键，确认能识别到物品。
    3. 确认规则后，再点“批量改价”或按批量热键。

    改价模式
    - 打折：输入 8 表示原价 * 0.8；输入 8.5 表示原价 * 0.85。
    - 统一加减：输入 -5 表示原价减 5；输入 +5 或 5 表示原价加 5。
    - 取整方式可选四舍五入、向下取整、向上取整。
    - 最终价格低于 1 时，一律按 1 标价。

    安全确认
    - 打折小于 5 折会二次确认。
    - 打折小于 1 折会强烈确认。
    - 统一减价会在执行前确认。

    颜色设置
    - 边框颜色用于识别搜索高亮边框，默认 E7B477。
    - 中心颜色用于排除空格，默认 070707。
    - 修改后点击“保存设置”，无需重启。

    常见失败
    - F4 识别为 0：先确认仓库里搜索了“物品”，或调整边框颜色。
    - 复制价格失败：确认右键物品后价格输入框会选中当前数字。
    - 热键无效：检查两个热键不要相同，且不要被其他软件占用。
    )

    Gui, Help:New, +OwnerMain, 使用说明
    Gui, Help:Font, s10, Microsoft YaHei
    Gui, Help:Margin, 12, 12
    Gui, Help:Add, Edit, w560 h420 ReadOnly -Wrap, %help%
    Gui, Help:Add, Button, x240 y+10 w90 h30 gHelpGuiClose, 关闭
    Gui, Help:Show
}

HelpGuiClose:
HelpGuiEscape:
    Gui, Help:Destroy
Return

SetStatus(text) {
    Gui, Main:Default
    GuiControl,, StatusText, %text%
}

NormalizeHex(value, default := "") {
    text := Trim(value)
    text := RegExReplace(text, "i)^(#|0x)")
    StringUpper, text, text
    if (RegExMatch(text, "^[0-9A-F]{6}$"))
        return text
    return default
}

NormalizeRounding(value) {
    if (value = "Floor" || value = "向下取整")
        return "Floor"
    if (value = "Ceil" || value = "向上取整")
        return "Ceil"
    return "Round"
}

RoundingTextToMode(value) {
    if (value = "向下取整")
        return "Floor"
    if (value = "向上取整")
        return "Ceil"
    return "Round"
}

IsNumberText(value) {
    return RegExMatch(Trim(value), "^[+-]?\d+(\.\d+)?$")
}

QuoteArg(value) {
    q := Chr(34)
    return q . StrReplace(value, q, q . q) . q
}

CsvLine(fields*) {
    line := ""
    for index, value in fields {
        if (index > 1)
            line .= ","
        line .= CsvEscape(value)
    }
    return line
}

CsvEscape(value) {
    q := Chr(34)
    value := StrReplace(value, q, q . q)
    value := StrReplace(value, "`r`n", "`n")
    value := StrReplace(value, "`r", "`n")
    return q . value . q
}
