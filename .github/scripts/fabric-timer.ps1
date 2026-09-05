# fabric-timer.ps1 — RDP Fabric floating countdown overlay
# Shows:  Remaining: 345 min
#         05:44:59
# Logs every run to C:\ProgramData\RDPFabric\timer.log
param([int]$Minutes = 0)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$mutex = New-Object System.Threading.Mutex($false, 'Local\RDPFabricTimerOverlay')
if (-not $mutex.WaitOne(0)) { return }

$logPath = 'C:\ProgramData\RDPFabric\timer.log'
function Write-TLog([string]$m) {
    try { Add-Content -Path $logPath -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding ASCII } catch {}
}
Write-TLog ("timer start (pid {0}, session {1})" -f $PID, [System.Diagnostics.Process]::GetCurrentProcess().SessionId)

$deadlineFile = 'C:\ProgramData\RDPFabric\deadline.txt'
$script:deadline = $null
if (Test-Path $deadlineFile) {
    try {
        $script:deadline = [datetime]::Parse(
            (Get-Content $deadlineFile -Raw).Trim(),
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind
        )
    } catch { $script:deadline = $null }
}
if (-not $script:deadline) {
    $script:deadline = (Get-Date).AddMinutes($(if ($Minutes -gt 0) { $Minutes } else { 345 }))
}
Write-TLog ("deadline " + $script:deadline.ToString('o'))

$script:form = New-Object System.Windows.Forms.Form
$script:form.Text            = 'Fabric Timer'
$script:form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$script:form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$script:form.Location        = New-Object System.Drawing.Point(10, 10)
$script:form.ClientSize      = New-Object System.Drawing.Size(240, 50)
$script:form.TopMost         = $true
$script:form.ShowInTaskbar   = $false
$script:form.BackColor       = [System.Drawing.Color]::FromArgb(15, 15, 18)
$script:form.Opacity         = 0.90

$script:label = New-Object System.Windows.Forms.Label
$script:label.Dock      = [System.Windows.Forms.DockStyle]::Fill
$script:label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$script:label.Font      = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$script:label.ForeColor = [System.Drawing.Color]::FromArgb(0, 230, 140)
$script:label.Text      = "Remaining: -- min`r`n--:--:--"
$script:form.Controls.Add($script:label)

$script:form.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(70, 70, 78)), 1
    $e.Graphics.DrawRectangle($pen, 0, 0, $s.ClientSize.Width - 1, $s.ClientSize.Height - 1)
    $pen.Dispose()
})

$script:dragging   = $false
$script:dragOrigin = New-Object System.Drawing.Point(0, 0)
$onDown = { param($s, $e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:dragging = $true; $script:dragOrigin = $e.Location } }
$onMove = { param($s, $e) if ($script:dragging) { $script:form.Location = New-Object System.Drawing.Point(($script:form.Location.X + $e.X - $script:dragOrigin.X), ($script:form.Location.Y + $e.Y - $script:dragOrigin.Y)) } }
$onUp   = { $script:dragging = $false }
$script:label.Add_MouseDown($onDown); $script:label.Add_MouseMove($onMove); $script:label.Add_MouseUp($onUp)
$script:form.Add_MouseDown($onDown);  $script:form.Add_MouseMove($onMove);  $script:form.Add_MouseUp($onUp)
$script:label.Add_DoubleClick({ $script:form.Location = New-Object System.Drawing.Point(10, 10) })

$script:tick = New-Object System.Windows.Forms.Timer
$script:tick.Interval = 1000
$script:tick.Add_Tick({
    $total = [math]::Floor(($script:deadline - (Get-Date)).TotalSeconds)
    if ($total -le 0) {
        $script:label.Text = "Remaining: 0 min`r`n00:00:00"
        $script:label.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80)
        return
    }
    $min = [math]::Ceiling(($script:deadline - (Get-Date)).TotalMinutes)
    $clock = '{0:00}:{1:00}:{2:00}' -f [math]::Floor($total / 3600), [math]::Floor(($total % 3600) / 60), ($total % 60)
    $script:label.Text = "Remaining: ${min} min`r`n${clock}"
    if ($total -le 300)     { $script:label.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80) }
    elseif ($total -le 900) { $script:label.ForeColor = [System.Drawing.Color]::FromArgb(255, 176, 32) }
    else                    { $script:label.ForeColor = [System.Drawing.Color]::FromArgb(0, 230, 140) }
    if (-not $script:form.TopMost) { $script:form.TopMost = $true }
})
$script:tick.Start()

$script:keepTop = New-Object System.Windows.Forms.Timer
$script:keepTop.Interval = 30000
$script:keepTop.Add_Tick({ $script:form.TopMost = $false; $script:form.TopMost = $true })
$script:keepTop.Start()

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($script:form)
Write-TLog "timer exit"
