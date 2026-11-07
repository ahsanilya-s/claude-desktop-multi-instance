<#
    Draws the picker with sample data and saves docs\assets\picker.png. The picker is drawn off-screen,
    and the icons use a plain placeholder picture, so no Anthropic artwork ends up in the repository.

        powershell -NoProfile -ExecutionPolicy Bypass -File tools\New-Screenshot.ps1

    Nothing outside a temporary folder is changed: APPDATA and LOCALAPPDATA point there while it runs.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outFile = Join-Path $repoRoot 'docs\assets\picker.png'
$work = Join-Path ([IO.Path]::GetTempPath()) ('cdmi-shot-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$savedEnv = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA }
New-Item -ItemType Directory -Path $work | Out-Null
try {
    Copy-Item (Join-Path $repoRoot 'Open-ClaudeInstance.ps1') $work
    $env:APPDATA = Join-Path $work 'Roaming'
    $env:LOCALAPPDATA = Join-Path $work 'Local'
    New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null
    . (Join-Path $work 'Open-ClaudeInstance.ps1')
    # Before anything is drawn, so the picture matches the picker on a high-DPI screen.
    [void][ClaudeInstWin]::SetProcessDPIAware()

    # Placeholder base picture: a plain rounded square.
    $bmp = New-Object System.Drawing.Bitmap(256, 256)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $shape = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = 64
    $shape.AddArc(8, 8, $r, $r, 180, 90); $shape.AddArc(248 - $r, 8, $r, $r, 270, 90)
    $shape.AddArc(248 - $r, 248 - $r, $r, $r, 0, 90); $shape.AddArc(8, 248 - $r, $r, $r, 90, 90)
    $shape.CloseFigure()
    $fillBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#94A3B8'))
    $g.FillPath($fillBrush, $shape)
    $fillBrush.Dispose(); $shape.Dispose(); $g.Dispose()
    $bmp.Save($BasePng, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    # Sample setup: Claude 2 "Work" is open, Claude 3 "Client A" is closed, Claude 4 is new.
    function Get-ClaudePackage { $null }
    function Get-ClaudeExe { $null }
    Save-Config ([pscustomobject]@{ mainLabel = 'Personal'; instances = @(
        [pscustomobject]@{ name = 'Instance2'; number = 2; label = 'Work'; shortcut = '' }
        [pscustomobject]@{ name = 'Instance3'; number = 3; label = 'Client A'; shortcut = '' }
        [pscustomobject]@{ name = 'Instance4'; number = 4; label = ''; shortcut = '' }
    ) })
    $sampleRunning = @(
        [pscustomobject]@{ ProcessId = 1; CreationDate = (Get-Date); CommandLine = 'claude.exe' }
        [pscustomobject]@{ ProcessId = 2; CreationDate = (Get-Date); CommandLine = "claude.exe --user-data-dir=`"$(Get-InstanceDir 'Instance2')`"" }
    )
    function Get-ClaudeAppProcess { $sampleRunning }
    function Test-SignedIn([string]$Dir) { $Dir -notlike '*Instance4' }

    New-BadgeIcon ([string][char]0x2261) '#334155' (Join-Path $IconDir 'claude-picker.ico')
    New-Item -ItemType Directory -Force -Path (Split-Path $outFile) | Out-Null
    Show-Picker $outFile
    Write-Host "Saved $outFile"

    # Social card for link previews: text and simple shapes only, no logos.
    $cardFile = Join-Path $repoRoot 'docs\assets\social-card.png'
    $card = New-Object System.Drawing.Bitmap(1200, 630)
    $g = [System.Drawing.Graphics]::FromImage($card)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#0F172A'))
    $px = [System.Drawing.GraphicsUnit]::Pixel
    $regular = [System.Drawing.FontStyle]::Regular
    $fTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 50, $regular, $px)
    $fSub = New-Object System.Drawing.Font('Segoe UI', 36, $regular, $px)
    $fSmall = New-Object System.Drawing.Font('Segoe UI', 26, $regular, $px)
    $fWin = New-Object System.Drawing.Font('Segoe UI Semibold', 24, $regular, $px)
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $soft = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#CBD5E1'))
    $dim = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#94A3B8'))
    $winFill = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#1E293B'))
    $lineFill = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#334155'))
    $dot = [string][char]0x00B7
    $g.DrawString('claude-desktop-multi-instance', $fTitle, $white, 64, 70)
    $g.DrawString("Run several Claude Desktop`naccounts side by side`non Windows", $fSub, $soft, 64, 165)
    $g.DrawString("Free $dot MIT licence $dot one PowerShell script $dot unofficial", $fSmall, $dim, 64, 530)
    $sampleWindows = @(@('Claude 1 - Personal', '#64748B'), @('Claude 2 - Work', '#2563EB'), @('Claude 3 - Client A', '#16A34A'))
    for ($i = 0; $i -lt $sampleWindows.Count; $i++) {
        $x = 700 + $i * 50; $y = 190 + $i * 85
        $accent = [System.Drawing.ColorTranslator]::FromHtml($sampleWindows[$i][1])
        $barFill = New-Object System.Drawing.SolidBrush($accent)
        $pen = New-Object System.Drawing.Pen($accent, 2)
        $g.FillRectangle($winFill, $x, $y, 400, 230)
        $g.FillRectangle($barFill, $x, $y, 400, 44)
        $g.DrawRectangle($pen, $x, $y, 400, 230)
        $g.DrawString($sampleWindows[$i][0], $fWin, $white, ($x + 14), ($y + 7))
        foreach ($row in 0..3) { $g.FillRectangle($lineFill, ($x + 18), ($y + 66 + $row * 34), (300 - $row * 40), 14) }
        $barFill.Dispose(); $pen.Dispose()
    }
    foreach ($d in $fTitle, $fSub, $fSmall, $fWin, $white, $soft, $dim, $winFill, $lineFill, $g) { $d.Dispose() }
    $card.Save($cardFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $card.Dispose()
    Write-Host "Saved $cardFile"
} finally {
    $env:APPDATA = $savedEnv.APPDATA
    $env:LOCALAPPDATA = $savedEnv.LOCALAPPDATA
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
