<#
.synopsis
  Standard publish flow: kill port -> build web -> start static server
.DESCRIPTION
  1) Find listener on <Port> and force-kill it (netstat + taskkill)
  2) flutter build web --release
  3) npx serve -s build/web -l <Port> in background (log: _serve.log)
  4) Verify listening + HTTP 200, print access URL
.EXAMPLE
  ./_rebuild_serve.ps1              # default port 8080
  ./_rebuild_serve.ps1 -Port 9000   # custom port
  ./_rebuild_serve.ps1 -SkipBuild   # skip build (e.g. just built)
#>
param(
    [int]$Port = 8080,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

# ---------- [1/4] kill port ----------
Write-Host "==> [1/4] check port $Port" -ForegroundColor Cyan
$found = $false
netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING" | ForEach-Object {
    $procId = ($_ -split '\s+')[-1]
    if ($procId -and $procId -ne '0') {
        $found = $true
        Write-Host "    kill PID $procId on port $Port" -ForegroundColor Yellow
        taskkill /PID $procId /F | Out-Null
    }
}
if (-not $found) {
    Write-Host "    no listener on port $Port" -ForegroundColor DarkGray
} else {
    Start-Sleep -Seconds 1  # wait for port release
}

# ---------- [2/4] build ----------
if (-not $SkipBuild) {
    Write-Host "==> [2/4] flutter build web --release" -ForegroundColor Cyan
    flutter build web --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "BUILD FAILED, abort (server not started)"
        exit 1
    }
    Write-Host "    build OK: build/web" -ForegroundColor Green
} else {
    Write-Host "==> [2/4] skip build (-SkipBuild)" -ForegroundColor DarkGray
}

# ---------- [3/4] start ----------
Write-Host "==> [3/4] start node _serve_web.js on port $Port" -ForegroundColor Cyan
Remove-Item _serve.log, _serve.err.log -ErrorAction SilentlyContinue
Start-Process -FilePath "node" -ArgumentList "_serve_web.js", "$Port", "build/web" `
    -RedirectStandardOutput "_serve.log" -RedirectStandardError "_serve.err.log" `
    -WindowStyle Hidden | Out-Null

# ---------- [4/4] verify (poll up to 15s) ----------
Write-Host "==> [4/4] verify" -ForegroundColor Cyan
$ok = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    if (netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING") { $ok = $true; break }
}
if (-not $ok) {
    Write-Host "    port $Port NOT listening, check _serve.err.log:" -ForegroundColor Red
    Get-Content _serve.err.log -Tail 10 -ErrorAction SilentlyContinue
    exit 1
}
$code = curl.exe -s -o NUL -w "%{http_code}" "http://localhost:$Port/"
Write-Host "    listening OK, HTTP $code"
Write-Host "    open: http://localhost:$Port/" -ForegroundColor Green
