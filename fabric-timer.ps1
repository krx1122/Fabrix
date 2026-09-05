# ═══════════════════════════════════════════════════════════════════════════
#  fabric-timer.ps1 — RDP Fabric floating countdown overlay (v5.2)
#
#  Displays two lines:
#      Remaining: 345 min
#      05:44:59
#
#  • Reads the session deadline from C:\ProgramData\RDPFabric\deadline.txt
#    (the workflow writes this file in Phase 0).
#  • Standalone run with an explicit duration:
#        powershell -NoProfile -ExecutionPolicy Bypass -File fabric-timer.ps1 -Minutes 120
#  • Draggable · always-on-top · double-click resets to top-left
#  • Single-instance via mutex · orange under 15 min, red under 5 min
# ═══════════════════════════════════════════════════════════════════════════
param([int]$Minutes = 0)

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$mutex = New-Object System.Threading.Mutex($false, 'Local\RDPFabricTimerOverlay')
if (-not $mutex.WaitOne(0)) { return }

$deadlineFile = 'C:\ProgramData\RDPFabric\deadline.txt'
$deadline = $null
if (Test-Path $deadlineFile) {
    try {
        $deadline = [datetime]::Parse(
            (Get-Content $deadlineFile -Raw).Trim(),
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind
        )
    } catch { $deadline = $null }
}
if (-not $deadline) {
    $deadline = (Get-Date).AddMinutes($(if ($Minutes -gt 0) { $Minutes } else { 345 }))
}

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition    = [System.Windows.Forms.FormStartPosition]::Manual
$form.Location         = New-Object System.Drawing.Point(10, 10)
$form.ClientSize       = New-Object System.Drawing.Size(240, 50)
$form.TopMost          = $true
$form.ShowInTaskbar    = $false
$form.BackColor        = [System.Drawing.Color]::FromArgb(15, 15, 18)
$form.Opacity          = 0.90

$label = New-Object System.Windows.Forms.Label
$label.Dock       = [System.Windows.Forms.DockStyle]::Fill
$label.TextAlign  = [System.Drawing.ContentAlignment]::MiddleCenter
$label.Font       = New-Object System.Drawing.Font('Consolas', 12, [System.Drawing.FontStyle]::Bold)
$label.ForeColor  = [System.Drawing.Color]::FromArgb(0, 230, 140)
$label.Text       = "Remaining: -- min`r`n--:--:--"
$form.Controls.Add($label)

$form.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(70, 70, 78)), 1
    $e.Graphics.DrawRectangle($pen, 0, 0, $s.ClientSize.Width - 1, $s.ClientSize.Height - 1)
    $pen.Dispose()
})

# Drag to move
$script:dragging  = $false
$script:dragOrigin = New-Object System.Drawing.Point(0, 0)
$onDown = { param($s, $e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:dragging = $true; $script:dragOrigin = $e.Location } }
$onMove = { param($s, $e) if ($script:dragging) { $form.Location = New-Object System.Drawing.Point(($form.Location.X + $e.X - $script:dragOrigin.X), ($form.Location.Y + $e.Y - $script:dragOrigin.Y)) } }
$onUp   = { $script:dragging = $false }
$label.Add_MouseDown($onDown); $label.Add_MouseMove($onMove); $label.Add_MouseUp($onUp)
$form.Add_MouseDown($onDown);  $form.Add_MouseMove($onMove);  $form.Add_MouseUp($onUp)
$label.Add_DoubleClick({ $form.Location = New-Object System.Drawing.Point(10, 10) })

# Countdown tick (1 s)
$tick = New-Object System.Windows.Forms.Timer
$tick.Interval = 1000
$tick.Add_Tick({
    $total = [math]::Floor(($deadline - (Get-Date)).TotalSeconds)
    if ($total -le 0) {
        $label.Text = "Remaining: 0 min`r`n00:00:00"
        $label.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80)
        return
    }
    $min = [math]::Ceiling(($deadline - (Get-Date)).TotalMinutes)
    $clock = '{0:00}:{1:00}:{2:00}' -f [math]::Floor($total / 3600), [math]::Floor(($total % 3600) / 60), ($total % 60)
    $label.Text = "Remaining: ${min} min`r`n${clock}"
    if ($total -le 300)     { $label.ForeColor = [System.Drawing.Color]::FromArgb(255, 80, 80) }
    elseif ($total -le 900) { $label.ForeColor = [System.Drawing.Color]::FromArgb(255, 176, 32) }
    else                    { $label.ForeColor = [System.Drawing.Color]::FromArgb(0, 230, 140) }
    if (-not $form.TopMost) { $form.TopMost = $true }
})
$tick.Start()

# Re-assert topmost every 30 s (survives fullscreen apps stealing Z-order)
$keepTop = New-Object System.Windows.Forms.Timer
$keepTop.Interval = 30000
$keepTop.Add_Tick({ $form.TopMost = $false; $form.TopMost = $true })
$keepTop.Start()

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
