# AR measure (Web preview) interaction regression script.
#
# Purpose: one command runs the whole chain "tap -> snap -> adopt -> area/volume -> screenshot"
#          for style & interaction regression. iOS LiDAR cannot be built on Windows, so the
#          Web preview is the only automatable acceptance surface; it shares the same business
#          logic (readings, error band, area/volume, wording) with the real device.
#
# Deps: agent-browser (global; reuses local Chrome) + static server on 8080.
#   install : npm install -g --allow-scripts=agent-browser agent-browser
#   serve   : python -m http.server 8080 -d build\web   (after flutter build web --release)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\ar_preview_smoke.ps1            # full (does login)
#   powershell -ExecutionPolicy Bypass -File tools\ar_preview_smoke.ps1 -SkipLogin # reuse saved state
#
# Key techniques (pitfalls already solved - read before editing):
#   1. Flutter Web needs the semantics tree enabled, or widgets cannot be located:
#      eval "document.querySelector('flt-semantics-placeholder').click()"
#   2. Canvas (CustomPaint) taps CANNOT use `agent-browser mouse` (coordinates unreliable).
#      Dispatch PointerEvent directly on `flutter-view`. Dispatch ONLY on flutter-view:
#      dispatching on flt-glass-pane delivers every event twice (one tap becomes A+B).
#   3. Widgets (tabs/buttons) are clicked via semantics refs: snapshot -i -> click eNN.
#      Never click buttons by pixel coordinates: panel height changes with state.
#   4. Fixed viewport 430x900; canvas spans x in [35,395], y in [140,630].
#   5. This file is kept ASCII-only on purpose: Windows PowerShell 5.1 decodes non-BOM files
#      as ANSI, so Chinese literals would be mangled. Chinese strings are built from code points.

param(
  [string]$BaseUrl = "http://localhost:8080",
  [string]$OutDir = "build\ar_smoke",
  [switch]$SkipLogin
)

$ErrorActionPreference = "Stop"
# Make CLI (UTF-8) output decode correctly so Chinese semantic names can be matched.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDirAbs = (Resolve-Path $OutDir).Path

# Chinese literals built from code points (ASCII-safe source).
function U { param([int[]]$c) -join ($c | ForEach-Object { [char]$_ }) }
$T_START  = U 0x5F00,0x59CB,0x4F7F,0x7528                    # 开始使用
$T_NEXT   = U 0x4E0B,0x4E00,0x6B65                           # 下一步
$T_ID     = U 0x6768,0x7389,0x5A77                           # 杨玉婷 (施工监理)
$T_PROJ   = U 0x5357,0x65B9,0x79D1,0x6280,0x5927,0x5B66        # 南方科技大学 (project prefix)
$T_LINE   = U 0x76F4,0x7EBF                                   # 直线
$T_AREA   = U 0x9762,0x79EF                                   # 面积
$T_VOL    = U 0x4F53,0x79EF                                   # 体积
$T_ADOPT  = U 0x91C7,0x7EB3,0x672C,0x7EC4                     # 采纳本组
$T_DATA   = U 0x67E5,0x770B,0x6570,0x636E                     # 查看数据

function Ab { & agent-browser @args }

function Shot {
  param([string]$Name)
  $p = Join-Path $OutDirAbs "$Name.png"
  Ab screenshot $p | Out-Null
  Write-Host "  [shot] $Name.png"
}

function EnableSemantics {
  Ab eval "(()=>{const p=document.querySelector('flt-semantics-placeholder');if(p)p.click();return 'sem';})()" | Out-Null
  Start-Sleep -Milliseconds 900
}

function Snap {
  (Ab snapshot -i) -join "`n"
}

# Click a widget by its semantic name prefix.
#
# Refs change on every snapshot, so always re-query. Must RETRY: Flutter rebuilds its
# semantics tree on re-render, so a name visible in one snapshot may be gone in the next.
function ClickByName {
  param([string]$Name, [int]$Tries = 8)
  for ($i = 0; $i -lt $Tries; $i++) {
    $text = Snap
    $m = [regex]::Match($text, "button `"$([regex]::Escape($Name))[^`"]*`" \[ref=(e\d+)\]")
    if ($m.Success) {
      Ab click $m.Groups[1].Value | Out-Null
      Start-Sleep -Milliseconds 900
      return
    }
    Start-Sleep -Milliseconds 800
    EnableSemantics   # tree may have been torn down by a re-render / still loading
  }
  throw "widget not found: $Name"
}

function Get-Hash { (Ab eval "location.hash") -join "" }

# Semantic name may be present but the widget is disabled until the previous step lands;
# click and then verify the expected next screen before moving on.
function WaitForHash {
  param([string]$Want, [int]$Tries = 10)
  for ($i = 0; $i -lt $Tries; $i++) {
    if ((Get-Hash) -match [regex]::Escape($Want)) { return $true }
    Start-Sleep -Milliseconds 900
  }
  return $false
}

# Canvas taps via DOM pointer events on flutter-view (one dispatch = exactly one tap).
function TapCanvas {
  param([int[]]$Xs, [int[]]$Ys)
  $pts = for ($i = 0; $i -lt $Xs.Count; $i++) { "[$($Xs[$i]),$($Ys[$i])]" }
  $js = "(async()=>{const t=document.querySelector('flutter-view');" +
        "const tap=(x,y)=>{const mk=(e)=>new PointerEvent(e,{bubbles:true,cancelable:true,composed:true," +
        "clientX:x,clientY:y,pointerId:9,pointerType:'touch',isPrimary:true,button:0," +
        "buttons:e==='pointerup'?0:1,width:1,height:1,pressure:e==='pointerup'?0:0.5});" +
        "t.dispatchEvent(mk('pointerdown'));t.dispatchEvent(mk('pointerup'));};" +
        "for(const p of [$($pts -join ',')]){tap(p[0],p[1]);await new Promise(r=>setTimeout(r,650));}" +
        "return 'taps';})()"
  Ab eval $js | Out-Null
  Start-Sleep -Milliseconds 700
}

function Adopt { ClickByName $T_ADOPT }

function SwitchMode {
  param([string]$Name)
  ClickByName $Name
  Start-Sleep -Milliseconds 900   # let the panel rebuild before tapping the canvas
}

# Demo login: 开始使用 -> identity -> 下一步 -> project -> 开始使用
#
# Each step is followed by a hash check: onboarding is a state machine, and clicking
# "next" before the previous step commits leaves the flow half-done (the app then
# restarts at the identity step on the next reload).
function Invoke-Login {
  Ab open "$BaseUrl" | Out-Null
  Start-Sleep -Seconds 7
  EnableSemantics
  ClickByName $T_START
  Start-Sleep -Seconds 2
  EnableSemantics
  ClickByName $T_ID
  Start-Sleep -Milliseconds 1200
  ClickByName $T_NEXT
  Start-Sleep -Seconds 2
  EnableSemantics
  ClickByName $T_PROJ
  Start-Sleep -Milliseconds 1400        # project selection must commit first
  ClickByName $T_START
  if (-not (WaitForHash "#/home")) { throw "login did not reach #/home" }
}

# Do not rely on saved state: `state load` restores the saved URL/tab and can fight
# with the navigation below. Detect the login page from the semantics instead.
function EnsureLoggedIn {
  $snap = Snap
  if ($snap -match [regex]::Escape($T_START)) {
    Write-Host "  login page detected -> running demo login"
    Invoke-Login
    # NOTE: deliberately no `state save` here - it writes a browser-state file into the
    # repo root (and `state load` fights with the navigation below). Login is cheap enough.
  } else {
    Write-Host "  session reuse: already logged in"
  }
}

Write-Host "== AR measure Web preview regression =="

Ab set viewport 430 900 | Out-Null

Write-Host "[1/6] ensure logged in"
if (-not $SkipLogin) { EnsureLoggedIn } else { Write-Host "  -SkipLogin: keep current session" }
if (-not ((Get-Hash) -match "home")) {
  Write-Host "  not at #/home yet -> login"
  Invoke-Login
}

Write-Host "[2/6] open AR measure (Web preview)"
Ab open "$BaseUrl/#/measure/ar" | Out-Null
Start-Sleep -Seconds 6
EnableSemantics
# go_router may bounce back to home on a cold load; retry once.
if (-not ((Snap) -match [regex]::Escape($T_LINE))) {
  Write-Host "  AR route not ready, retry"
  Ab open "$BaseUrl/#/measure/ar" | Out-Null
  Start-Sleep -Seconds 5
  EnableSemantics
}

Write-Host "[3/6] line mode: tap (with snapping) -> adopt"
SwitchMode $T_LINE
# Tap order matters for the screenshot: the snap hint reflects the LAST tap, so the
# snapping tap goes second (otherwise the hint is overwritten by the non-snapping tap).
TapCanvas -Xs 380 -Ys 560
TapCanvas -Xs 155 -Ys 300              # near a guide line -> snapping hint visible
Shot "01_line_taps"
Adopt
Shot "02_line_adopted"

Write-Host "[4/6] area mode: continuous length -> width, face auto-generated"
SwitchMode $T_AREA
TapCanvas -Xs 80,360 -Ys 200,520
Adopt
TapCanvas -Xs 90,200 -Ys 210,560
Adopt
Shot "03_area_face"

Write-Host "[5/6] volume mode: continuous length -> width -> height, cube auto-generated"
SwitchMode $T_VOL
TapCanvas -Xs 90,350 -Ys 480,470
Adopt
TapCanvas -Xs 90,360 -Ys 460,300
Adopt
TapCanvas -Xs 90,150 -Ys 460,260
Adopt
Shot "04_volume_cube"

Write-Host "[6/6] data sheet (list + error band)"
ClickByName $T_DATA
Start-Sleep -Milliseconds 900
Shot "05_data_sheet"

Ab close | Out-Null
Write-Host "== done, screenshots in $OutDir =="
