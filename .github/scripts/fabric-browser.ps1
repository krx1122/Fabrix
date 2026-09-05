# fabric-browser.ps1 — auto-open a site in the default browser (Edge) at logon
# Single-instance via mutex + 8-min lock + running-window check (no duplicate tabs)
# Usage: powershell -File fabric-browser.ps1 [-Url "https://fabric-x-xi.vercel.app"] [-Root "C:\ProgramData\RDPFabric"]
param(
    [string]$Url  = 'https://fabric-x-xi.vercel.app',
    [string]$Root = 'C:\ProgramData\RDPFabric'
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# Normalize URL
if ($Url -and ($Url -notmatch '^https?://')) { $Url = "https://$Url" }

$mutex = New-Object System.Threading.Mutex($false, 'Local\RDPFabricBrowserOpen')
if (-not $mutex.WaitOne(0)) { return }

$hostPart = [string]$Url
try { $hostPart = ([System.Uri]$Url).Host } catch {}

# 8-minute lock so re-logon doesn't spam a second window
$lock = Join-Path $Root '.browser-launched'
if (Test-Path -LiteralPath $lock) {
    try {
        $age = (Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime
        if ($age.TotalMinutes -lt 8) { return }
    } catch {}
}

# 1) Edge first (default browser on every Windows runner image)
$browser = $null
$browserName = ''
foreach ($p in @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe",
    "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
)) {
    if (Test-Path -LiteralPath $p) { $browser = $p; $browserName = 'msedge'; break }
}

# 2) OS default browser fallback
if (-not $browser) {
    try {
        $def = (Get-ItemProperty 'Registry::HKEY_CLASSES_ROOT\http\shell\open\command' -ErrorAction SilentlyContinue).'(default)'
        if ($def) {
            $m = [regex]::Match($def, '"([^"]+\.exe)"')
            if ($m.Success -and (Test-Path -LiteralPath $m.Groups[1].Value)) { $browser = $m.Groups[1].Value; $browserName = 'default' }
        }
    } catch {}
}

# 3) Chrome fallback
if (-not $browser) {
    foreach ($p in @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )) {
        if (Test-Path -LiteralPath $p) { $browser = $p; $browserName = 'chrome'; break }
    }
}
if (-not $browser) { return }

# Don't double-open if a window showing this site is already up
$probe = Get-CimInstance Win32_Process -Filter "Name='$browserName.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and ($_.CommandLine -like "*$hostPart*" -or $_.CommandLine -like "*$Url*") }
if ($probe) { return }

$args = @()
if ($browserName -in @('msedge','chrome')) {
    $args = @(
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-session-crashed-bubble',
        '--disable-background-networking',
        $Url
    )
} else {
    $args = @($Url)
}
Start-Process -FilePath $browser -ArgumentList $args
Set-Content -Path $lock -Value (Get-Date -Format o) -Encoding ASCII
