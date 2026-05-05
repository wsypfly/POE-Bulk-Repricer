param(
    [switch]$InstallPyInstaller
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = if ($ScriptRoot -and (Test-Path $ScriptRoot)) { $ScriptRoot } else { (Get-Location).Path }
$ReleaseRoot = Join-Path $Root "release"
$BuildRoot = Join-Path $Root "_build"
$ToolBaseName = "POE" + [char]0x6807 + [char]0x4EF7 + [char]0x5DE5 + [char]0x5177
$ToolAhkName = $ToolBaseName + ".ahk"
$ToolExeName = $ToolBaseName + ".exe"
$OpenSourceName = "01-" + [char]0x5F00 + [char]0x6E90 + [char]0x7248
$AhkShareName = "02-AHK" + [char]0x5206 + [char]0x4EAB + [char]0x7248
$FullPackName = "03-" + [char]0x5168 + [char]0x6253 + [char]0x5305 + [char]0x7248
$OpenSourceDir = Join-Path $ReleaseRoot $OpenSourceName
$AhkShareDir = Join-Path $ReleaseRoot $AhkShareName
$FullPackDir = Join-Path $ReleaseRoot $FullPackName
$Ahk2Exe = "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
$AhkBaseCandidates = @(
    "C:\Program Files\AutoHotkey\v1.1.37.02\Unicode 64-bit.bin",
    "C:\Program Files\AutoHotkey\v1.1.37.02\Unicode 32-bit.bin",
    "C:\Program Files\AutoHotkey\Compiler\Unicode 64-bit.bin",
    "C:\Program Files\AutoHotkey\Compiler\Unicode 32-bit.bin"
)

function Copy-CommonFiles {
    param(
        [string]$Destination,
        [bool]$IncludePython,
        [bool]$IncludeAhk
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root "settings.ini") -Destination $Destination -Force
    Copy-Item -LiteralPath (Join-Path $Root "README.txt") -Destination $Destination -Force
    if ($IncludeAhk) {
        Copy-Item -LiteralPath (Join-Path $Root $ToolAhkName) -Destination $Destination -Force
    }
    if ($IncludePython) {
        Copy-Item -LiteralPath (Join-Path $Root "market_detect_items.py") -Destination $Destination -Force
        Copy-Item -LiteralPath (Join-Path $Root "requirements.txt") -Destination $Destination -Force
    }
}

function Test-PyInstaller {
    try {
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $null = & python -m PyInstaller --version 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $oldPreference
    }
}

if (Test-Path $ReleaseRoot) {
    $resolvedRoot = [IO.Path]::GetFullPath($Root)
    $resolvedRelease = [IO.Path]::GetFullPath($ReleaseRoot)
    if (-not $resolvedRelease.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove release directory outside project root: $resolvedRelease"
    }
    Remove-Item -LiteralPath $ReleaseRoot -Recurse -Force
}
if (Test-Path $BuildRoot) {
    Remove-Item -LiteralPath $BuildRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $ReleaseRoot, $BuildRoot | Out-Null

if (-not (Test-PyInstaller)) {
    if ($InstallPyInstaller) {
        & python -m pip install pyinstaller
    } else {
        throw "PyInstaller is not installed. Re-run with -InstallPyInstaller or install it manually: python -m pip install pyinstaller"
    }
}

if (-not (Test-Path $Ahk2Exe)) {
    throw "Ahk2Exe not found: $Ahk2Exe"
}
$AhkBase = $AhkBaseCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $AhkBase) {
    throw "AutoHotkey v1 base file not found. Expected one of: $($AhkBaseCandidates -join '; ')"
}

$PyDist = Join-Path $BuildRoot "py_dist"
$PyWork = Join-Path $BuildRoot "py_work"
& python -m PyInstaller `
    --clean `
    --onefile `
    --name market_detect_items `
    --distpath $PyDist `
    --workpath $PyWork `
    --specpath $BuildRoot `
    (Join-Path $Root "market_detect_items.py")

$DetectorExe = Join-Path $PyDist "market_detect_items.exe"
if (-not (Test-Path $DetectorExe)) {
    throw "Detector exe was not created: $DetectorExe"
}

$AhkExe = Join-Path $BuildRoot "poe_pricer.exe"
& $Ahk2Exe /in (Join-Path $Root $ToolAhkName) /out $AhkExe /base $AhkBase
for ($i = 0; $i -lt 20; $i++) {
    $builtAhk = Get-ChildItem -LiteralPath $BuildRoot -Filter "poe_pricer.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($builtAhk) {
        $AhkExe = $builtAhk.FullName
        break
    }
    Start-Sleep -Milliseconds 250
}
if (-not $builtAhk) {
    throw "AHK exe was not created: $AhkExe"
}

Copy-CommonFiles -Destination $OpenSourceDir -IncludePython $true -IncludeAhk $true

Copy-CommonFiles -Destination $AhkShareDir -IncludePython $false -IncludeAhk $true
Copy-Item -LiteralPath $DetectorExe -Destination $AhkShareDir -Force

Copy-CommonFiles -Destination $FullPackDir -IncludePython $false -IncludeAhk $false
Copy-Item -LiteralPath $AhkExe -Destination (Join-Path $FullPackDir $ToolExeName) -Force
Copy-Item -LiteralPath $DetectorExe -Destination $FullPackDir -Force

Get-ChildItem -LiteralPath $ReleaseRoot -Directory | ForEach-Object {
    $zipPath = Join-Path $ReleaseRoot ($_.Name + ".zip")
    Compress-Archive -LiteralPath $_.FullName -DestinationPath $zipPath -Force
}

Write-Host "Release packages created under: .\release"
