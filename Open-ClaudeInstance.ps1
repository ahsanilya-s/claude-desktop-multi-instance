<#
.SYNOPSIS
    Runs several Claude Desktop windows ("instances") side by side on Windows, each signed in to its own account,
    and keeps them easy to tell apart.

.DESCRIPTION
    Claude Desktop normally runs once per Windows account. This script starts extra copies of the installed app,
    each with its own data folder (%APPDATA%\Claude-<Name>), so each copy has its own sign-in, settings and
    MCP servers. Your normal Claude (number 1, from the Start menu) is not changed.

    Every extra instance gets:
      - a number: your normal Claude is 1, the next one is 2, and so on
      - an optional label, such as "Work" or the account it is signed in to
      - its own icon: your installed Claude icon with a coloured number badge, made on your PC
      - its own desktop shortcut, named like "Claude 2 - Work"
      - the window title "Claude 2 - Work", shown in Alt+Tab and taskbar previews

    Sign in to an extra instance with your email address and the code from the email, typed into that
    instance's own window. Google or browser sign-in sends you back to your normal Claude instead.

    Opening an instance that is already open brings its window forward. Closing an instance with its X only
    hides it in the tray, where it keeps using memory; -Quit (or Quit in the picker) closes it the way
    Windows closes apps at sign-out. The Claude program is looked up each time, so app updates do not break
    the shortcuts.

    Unofficial: this project is not made, endorsed or supported by Anthropic.

.PARAMETER Name
    The instance to open, label or quit: letters, digits and dashes, up to 32 characters. Default: Instance2.
    Its data is kept in %APPDATA%\Claude-<Name>.

.PARAMETER Label
    Sets the instance's label, for example Work, without opening it. An empty label removes it.

.PARAMETER Picker
    Shows a small window that lists every instance. Press 1-9 or Enter to open one, Esc to close.

.PARAMETER List
    Lists the instances in the console: number, name, label, signed in, open, data folder.

.PARAMETER Setup
    Creates or rebuilds the icons and desktop shortcuts. On the first run it also prepares Claude 2.

.PARAMETER Quit
    Quits the instance given by -Name properly, which frees its memory. Never touches your normal Claude.

.PARAMETER Version
    Prints the version of this script.

.PARAMETER Snapshot
    With -Picker: saves an image of the picker to this path instead of showing it.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Open-ClaudeInstance.ps1 -Setup

    Creates the "Claude 2" and "Claude - choose instance" shortcuts on the desktop.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Open-ClaudeInstance.ps1 -Name Instance2

    Opens Claude 2, creating it and its shortcut on first use. This is what the "Claude 2" shortcut runs.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Open-ClaudeInstance.ps1 -Name Instance3 -Label Client

    Labels Claude 3 "Client". Its shortcut and window title become "Claude 3 - Client".

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Open-ClaudeInstance.ps1 -Name Instance2 -Quit

    Quits Claude 2 and frees its memory.

.NOTES
    Needs Windows PowerShell 5.1 (built into Windows 10 and 11) and Claude Desktop for Windows.
    Settings, icons and the title helper are kept next to this script. Keep the folder where it is, or run
    -Setup again after moving it.

.LINK
    https://github.com/ahsanilya-s/claude-desktop-multi-instance
#>
#Requires -Version 5.1
param(
    [ValidatePattern('^[A-Za-z0-9-]{1,32}$')]
    [string]$Name = 'Instance2',
    [string]$Label,
    [switch]$Picker,
    [switch]$List,
    [switch]$Setup,
    [switch]$Quit,
    [switch]$Version,
    [string]$Snapshot
)

$ToolVersion = '0.1.0'

if ($PSVersionTable.PSEdition -eq 'Core') {
    # Get-AppxPackage, the picker and the compiled title helper all need Windows PowerShell (.NET Framework).
    throw 'Open-ClaudeInstance.ps1 needs Windows PowerShell 5.1 (powershell.exe), which is built into Windows. PowerShell 7 (pwsh) is not supported.'
}

$ErrorActionPreference = 'Stop'
$Base       = $PSScriptRoot
$ScriptPath = $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $Base 'instances.json'
$IconDir    = Join-Path $Base 'icons'
$BasePng    = Join-Path $Base 'claude-256.png'
$KeeperExe  = Join-Path $Base 'bin\ClaudeTitleKeeper-v1.exe'
$Palette    = @('#2563EB', '#16A34A', '#9333EA', '#D97706', '#DB2777', '#0D9488', '#475569', '#DC2626')
$PickerLink = 'Claude - choose instance.lnk'
$NotInstalled = 'Claude Desktop is not installed for this Windows account. Install it from https://claude.ai/download and try again.'

Add-Type -AssemblyName System.Drawing
if (-not ('ClaudeInstWin' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ClaudeInstWin {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();

    // Asks an instance to quit the way Windows does at sign-out. Claude handles this itself
    // ("Windows session ending (close-app) - quitting the app") and closes properly.
    public static int AskToQuit(uint pid) {
        System.Collections.Generic.List<IntPtr> wins = new System.Collections.Generic.List<IntPtr>();
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p != pid) return true;
            StringBuilder c = new StringBuilder(256); GetClassName(h, c, 256);
            if (c.ToString() != "Chrome_WidgetWin_1") return true;
            StringBuilder t = new StringBuilder(512); GetWindowText(h, t, 512);
            if (t.Length > 0) wins.Add(h);
            return true;
        }, IntPtr.Zero);
        IntPtr r;
        foreach (IntPtr h in wins) {
            SendMessageTimeout(h, 0x0011, IntPtr.Zero, (IntPtr)1, 2, 5000, out r);  // WM_QUERYENDSESSION, close-app
            SendMessageTimeout(h, 0x0016, (IntPtr)1, (IntPtr)1, 2, 5000, out r);     // WM_ENDSESSION, close-app
        }
        return wins.Count;
    }
}
'@
}

# The title helper: a tiny program (about 2 MB of memory) that keeps an instance's window title while it runs.
# It is compiled here from the source below the first time it is needed, so no ready-made program is shipped.
$KeeperSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace ClaudeTitleKeeper {
    // Keeps one Claude instance's window title as "Claude N - Label" while that instance runs.
    // Arguments: <process id> <title file> <title prefix "Claude N">. Exits when the instance exits.
    static class Program {
        delegate bool EnumProc(IntPtr h, IntPtr l);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool SetWindowText(IntPtr h, string t);
        [DllImport("kernel32.dll")] static extern bool SetProcessWorkingSetSize(IntPtr p, IntPtr min, IntPtr max);

        // Renames the instance's window when its title is the app's own "Claude",
        // or an older title this helper gave it ("Claude N" or "Claude N - ...").
        static void Retitle(uint pid, string prefix, string wanted) {
            EnumWindows(delegate (IntPtr h, IntPtr l) {
                uint p; GetWindowThreadProcessId(h, out p);
                if (p != pid) return true;
                StringBuilder c = new StringBuilder(256); GetClassName(h, c, 256);
                if (c.ToString() != "Chrome_WidgetWin_1") return true;
                StringBuilder t = new StringBuilder(512); GetWindowText(h, t, 512);
                string title = t.ToString();
                if (title != wanted && (title == "Claude" || title == prefix || title.StartsWith(prefix + " - ")))
                    SetWindowText(h, wanted);
                return true;
            }, IntPtr.Zero);
        }

        static int Main(string[] args) {
            if (args.Length < 3) return 2;
            int pid;
            if (!int.TryParse(args[0], out pid)) return 2;
            string file = args[1], prefix = args[2];
            bool created;
            using (Mutex m = new Mutex(true, "Local\\ClaudeInstanceTitle-" + Path.GetFileNameWithoutExtension(file), out created)) {
                if (!created) return 0;
                Process p;
                try { p = Process.GetProcessById(pid); } catch { return 0; }
                DateTime stamp = DateTime.MinValue;
                string title = null;
                int round = 0;
                while (!p.HasExited) {
                    try {
                        DateTime t = File.GetLastWriteTimeUtc(file);
                        if (t != stamp) { stamp = t; title = File.ReadAllText(file, Encoding.UTF8).Trim(); }
                    } catch { }
                    if (!string.IsNullOrEmpty(title)) Retitle((uint)pid, prefix, title);
                    if (round++ % 200 == 1) SetProcessWorkingSetSize(Process.GetCurrentProcess().Handle, (IntPtr)(-1), (IntPtr)(-1));
                    p.WaitForExit(3000);
                }
            }
            return 0;
        }
    }
}
'@

# ---------------------------------------------------------------- helpers

function Show-Message([string]$Text, [string]$Kind = 'Information') {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($Text, 'Claude instances', 'OK', $Kind) | Out-Null
    } catch { Write-Host $Text }
}

function Get-ClaudePackage {
    Get-AppxPackage -Name 'Claude' -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending | Select-Object -First 1
}

function Get-ClaudeExe {
    $pkg = Get-ClaudePackage
    if ($pkg) {
        $exe = Join-Path $pkg.InstallLocation 'app\claude.exe'
        if (Test-Path $exe) { return $exe }
    }
    # The older per-user installer keeps versioned copies in %LOCALAPPDATA%\AnthropicClaude\app-<version>.
    $root = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    $app = Get-ChildItem $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
        Sort-Object { $v = $null; if ([version]::TryParse($_.Name.Substring(4), [ref]$v)) { $v } else { [version]'0.0' } } -Descending |
        ForEach-Object { Join-Path $_.FullName 'claude.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($app) { return $app }
    $stub = Join-Path $root 'claude.exe'
    if (Test-Path $stub) { return $stub }
    return $null
}

function Get-MainDataDir {
    $root = Join-Path $env:LOCALAPPDATA 'Claude-Data'
    if (Test-Path $root) {
        $d = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'config.json') } | Select-Object -First 1
        if ($d) { return $d.FullName }
    }
    return (Join-Path $env:APPDATA 'Claude')
}

function Get-InstanceDir([string]$InstName) { Join-Path $env:APPDATA "Claude-$InstName" }

# A best guess: once you are signed in, Claude keeps a token cache entry in config.json.
# Only the presence of that key is checked; the token itself is never read out or sent anywhere.
function Test-SignedIn([string]$Dir) {
    $f = Join-Path $Dir 'config.json'
    if (-not (Test-Path $f)) { return $false }
    try { return ((Get-Content $f -Raw) -match '"oauth:tokenCache') } catch { return $false }
}

function Get-Color([int]$Number) { $Palette[($Number - 2) % $Palette.Count] }

function Get-Title($Inst) {
    $t = "Claude $($Inst.number)"
    if ($Inst.label) { $t += " - $($Inst.label)" }
    return $t
}

# Top-level Claude Desktop processes (not its helper processes, and not Claude Code).
function Get-ClaudeAppProcess {
    @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and
        ($_.ExecutablePath -like '*\WindowsApps\Claude_*' -or $_.ExecutablePath -like '*\AnthropicClaude\*') -and
        ([string]$_.CommandLine) -notmatch '--type='
    })
}

# $Dir = instance data folder, or $null for your normal Claude.
# The oldest match wins: a just-launched copy that only hands over to the running one is newer.
function Find-ClaudePid($Processes, [string]$Dir) {
    foreach ($p in @($Processes | Sort-Object CreationDate)) {
        $cl = ([string]$p.CommandLine).ToLower()
        if ($Dir) {
            if ($cl.Contains(('--user-data-dir="' + $Dir + '"').ToLower())) { return [int]$p.ProcessId }
        } elseif ($cl -notmatch '--user-data-dir') {
            return [int]$p.ProcessId
        }
    }
    return 0
}

# ---------------------------------------------------------------- settings file

function Read-Config {
    $cfg = [pscustomobject]@{ mainLabel = 'Main'; instances = @() }
    if (Test-Path $ConfigPath) {
        try {
            $j = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.mainLabel) { $cfg.mainLabel = [string]$j.mainLabel }
            $cfg.instances = @($j.instances | Where-Object { $_ -and $_.name } | ForEach-Object {
                [pscustomobject]@{ name = [string]$_.name; number = [int]$_.number; label = [string]$_.label; shortcut = [string]$_.shortcut }
            })
        } catch { Write-Verbose "Ignoring a damaged settings file: $($_.Exception.Message)" }
    }
    # Pick up instance folders that are not in the settings file yet.
    Get-ChildItem $env:APPDATA -Directory -Filter 'Claude-*' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'Local State') } | ForEach-Object {
            $n = $_.Name.Substring(7)
            if ($n -match '^[A-Za-z0-9-]{1,32}$' -and -not (Find-Instance $cfg $n)) {
                $num = Get-NextNumber $cfg
                if ($n -match '^Instance(\d+)$' -and [int]$Matches[1] -ge 2 -and
                    -not ($cfg.instances | Where-Object { $_.number -eq [int]$Matches[1] })) { $num = [int]$Matches[1] }
                $cfg.instances += [pscustomobject]@{ name = $n; number = $num; label = ''; shortcut = '' }
            }
        }
    $cfg.instances = @($cfg.instances | Sort-Object number)
    return $cfg
}

function Save-Config($Cfg) {
    $out = [ordered]@{ mainLabel = $Cfg.mainLabel; instances = @($Cfg.instances) }
    ($out | ConvertTo-Json -Depth 4) | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Find-Instance($Cfg, [string]$InstName) {
    $Cfg.instances | Where-Object { $_.name -eq $InstName } | Select-Object -First 1
}

function Get-NextNumber($Cfg) {
    $m = 1
    foreach ($i in $Cfg.instances) { if ($i.number -gt $m) { $m = $i.number } }
    return $m + 1
}

# ---------------------------------------------------------------- icons and shortcuts

# The picture the icons start from: your installed Claude Desktop's own icon, copied once into this folder.
# Nothing from Anthropic is shipped with this script.
function Get-BaseImage {
    if (-not (Test-Path $BasePng)) {
        $pkg = Get-ClaudePackage
        $src = $null
        if ($pkg) { $src = Join-Path $pkg.InstallLocation 'assets\Square44x44Logo.targetsize-256_altform-unplated.png' }
        if ($src -and (Test-Path $src)) {
            Copy-Item $src $BasePng
        } else {
            $exe = Get-ClaudeExe
            if ($exe) { [System.Drawing.Icon]::ExtractAssociatedIcon($exe).ToBitmap().Save($BasePng, [System.Drawing.Imaging.ImageFormat]::Png) }
        }
    }
    if (Test-Path $BasePng) { return [System.Drawing.Image]::FromFile($BasePng) }
    # Claude Desktop is not installed: a plain square keeps the icons working until it is.
    $bmp = New-Object System.Drawing.Bitmap(256, 256)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#64748B'))
    $g.Dispose()
    return $bmp
}

# Writes a multi-size .ico: the base picture, with a round badge holding $Text if given.
function New-BadgeIcon([string]$Text, [string]$Color, [string]$Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    $src = Get-BaseImage
    $entries = New-Object System.Collections.ArrayList
    try {
        foreach ($s in 16, 20, 24, 32, 40, 48, 64, 256) {
            $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.SmoothingMode = 'AntiAlias'
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.PixelOffsetMode = 'HighQuality'
            $g.TextRenderingHint = 'AntiAlias'
            $g.DrawImage($src, 0, 0, $s, $s)
            if ($Text) {
                $f = 0.62; if ($s -le 24) { $f = 0.74 }
                $d = [single][Math]::Round($s * $f)
                $x = [single]($s - $d); $y = [single]($s - $d)
                $ring = [single][Math]::Max(1, [Math]::Round($s * 0.05))
                $brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($Color))
                $g.FillEllipse([System.Drawing.Brushes]::White, $x, $y, $d, $d)
                $g.FillEllipse($brush, $x + $ring, $y + $ring, $d - 2 * $ring, $d - 2 * $ring)
                $fs = 0.68; if ($Text.Length -gt 1) { $fs = 0.5 }
                $font = New-Object System.Drawing.Font('Segoe UI', [single]($d * $fs), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
                $sf = New-Object System.Drawing.StringFormat
                $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
                $g.DrawString($Text, $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF($x, ($y + $d * 0.03), $d, $d)), $sf)
                $font.Dispose(); $brush.Dispose(); $sf.Dispose()
            }
            $g.Dispose()
            $ms = New-Object System.IO.MemoryStream
            if ($s -ge 256) {
                # Large size: PNG, as Windows expects.
                $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            } else {
                # Small sizes: classic 32-bit bitmap, which every icon reader understands.
                $rect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
                $bd = $bmp.LockBits($rect, 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
                $pix = New-Object byte[] ($bd.Stride * $s)
                [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $pix, 0, $pix.Length)
                $bmp.UnlockBits($bd)
                $maskStride = [int]([Math]::Floor(($s + 31) / 32) * 4)
                $w = New-Object System.IO.BinaryWriter($ms)
                $w.Write([uint32]40); $w.Write([int32]$s); $w.Write([int32]($s * 2))
                $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0)
                $w.Write([uint32]($s * $s * 4 + $maskStride * $s))
                $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
                for ($r = $s - 1; $r -ge 0; $r--) { $w.Write($pix, $r * $bd.Stride, $s * 4) }
                $w.Write((New-Object byte[] ($maskStride * $s)))
                $w.Flush()
            }
            [void]$entries.Add(@($s, $ms.ToArray()))
            $bmp.Dispose(); $ms.Dispose()
        }
    } finally { $src.Dispose() }

    $file = [System.IO.File]::Create($Path)
    $bw = New-Object System.IO.BinaryWriter($file)
    try {
        $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$entries.Count)
        $offset = 6 + 16 * $entries.Count
        foreach ($e in $entries) {
            $wb = $e[0]; if ($wb -ge 256) { $wb = 0 }
            $bw.Write([byte]$wb); $bw.Write([byte]$wb); $bw.Write([byte]0); $bw.Write([byte]0)
            $bw.Write([uint16]1); $bw.Write([uint16]32)
            $bw.Write([uint32]$e[1].Length); $bw.Write([uint32]$offset)
            $offset += $e[1].Length
        }
        foreach ($e in $entries) { $bw.Write([byte[]]$e[1]) }
    } finally { $bw.Close() }
}

function Get-IconPath([int]$Number) {
    $p = Join-Path $IconDir "claude-$Number.ico"
    if (-not (Test-Path $p)) {
        if ($Number -le 1) { New-BadgeIcon '' '' $p } else { New-BadgeIcon ([string]$Number) (Get-Color $Number) $p }
    }
    return $p
}

function Get-SafeFileName([string]$s) { ($s -replace '[\\/:*?"<>|]', '').Trim() }

function Get-ShortcutDir { [Environment]::GetFolderPath('Desktop') }

function Save-Shortcut([string]$LinkPath, [string]$Arguments, [string]$Icon, [string]$Description) {
    $sh = New-Object -ComObject WScript.Shell
    $l = $sh.CreateShortcut($LinkPath)
    $l.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $l.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`" $Arguments"
    $l.WorkingDirectory = $Base
    $l.IconLocation = "$Icon,0"
    $l.WindowStyle = 7
    $l.Description = $Description
    $l.Save()
}

function Update-InstanceShortcut($Inst) {
    $link = Join-Path (Get-ShortcutDir) ((Get-SafeFileName (Get-Title $Inst)) + '.lnk')
    if ($Inst.shortcut -and $Inst.shortcut -ne $link -and (Test-Path $Inst.shortcut)) {
        Remove-Item $Inst.shortcut -ErrorAction SilentlyContinue
    }
    Save-Shortcut $link "-Name $($Inst.name)" (Get-IconPath $Inst.number) "Opens $(Get-Title $Inst), a separate Claude window"
    $Inst.shortcut = $link
}

function Update-PickerShortcut {
    $icon = Join-Path $IconDir 'claude-picker.ico'
    if (-not (Test-Path $icon)) { New-BadgeIcon ([string][char]0x2261) '#334155' $icon }
    Save-Shortcut (Join-Path (Get-ShortcutDir) $PickerLink) '-Picker' $icon 'Choose which Claude instance to open'
}

# ---------------------------------------------------------------- opening

function Get-KeeperExe {
    if (-not (Test-Path $KeeperExe)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $KeeperExe) | Out-Null
        Add-Type -TypeDefinition $KeeperSource -OutputAssembly $KeeperExe -OutputType WindowsApplication
    }
    return $KeeperExe
}

# The title helper reads the wanted title from this file, so a new label shows up within seconds.
function Write-TitleFile($Inst) {
    $dir = Join-Path $Base 'titles'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $file = Join-Path $dir "$($Inst.name).txt"
    [System.IO.File]::WriteAllText($file, (Get-Title $Inst), (New-Object System.Text.UTF8Encoding($false)))
    return $file
}

function Start-TitleKeeper($Inst) {
    $file = Write-TitleFile $Inst
    $dir = Get-InstanceDir $Inst.name
    $procId = 0
    $deadline = (Get-Date).AddSeconds(30)
    while ($procId -eq 0 -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 700
        $procId = Find-ClaudePid (Get-ClaudeAppProcess) $dir
    }
    if ($procId -eq 0) { return }
    Start-Process -FilePath (Get-KeeperExe) -ArgumentList @("$procId", "`"$file`"", "`"Claude $($Inst.number)`"")
}

# Quits an extra instance properly. Returns 'closed', 'not-open' or 'still-open'.
function Stop-Instance($Inst) {
    $procId = Find-ClaudePid (Get-ClaudeAppProcess) (Get-InstanceDir $Inst.name)
    if ($procId -eq 0) { return 'not-open' }
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    [void][ClaudeInstWin]::AskToQuit([uint32]$procId)
    if ($p -and -not $p.WaitForExit(15000)) { return 'still-open' }
    return 'closed'
}

function Open-Instance($Inst) {
    $exe = Get-ClaudeExe
    if (-not $exe) { Show-Message $NotInstalled 'Error'; return }
    $dir = Get-InstanceDir $Inst.name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Start-Process -FilePath $exe -ArgumentList "--user-data-dir=`"$dir`""
    Start-TitleKeeper $Inst
}

function Open-Main {
    $pkg = Get-ClaudePackage
    if ($pkg) {
        $appId = (Get-AppxPackageManifest $pkg).Package.Applications.Application |
            Where-Object { $_.Id -eq 'Claude' } | Select-Object -First 1
        if ($appId) { Start-Process "shell:AppsFolder\$($pkg.PackageFamilyName)!Claude"; return }
    }
    $exe = Get-ClaudeExe
    if ($exe) { Start-Process -FilePath $exe } else { Show-Message $NotInstalled 'Error' }
}

# Creates or rebuilds the icons and desktop shortcuts. On the first run it also prepares Claude 2.
function Invoke-Setup {
    $cfg = Read-Config
    if (@($cfg.instances).Count -eq 0) {
        $cfg.instances = @([pscustomobject]@{ name = 'Instance2'; number = 2; label = ''; shortcut = '' })
    }
    # Start the icons again from the installed app's current icon.
    Remove-Item $BasePng -ErrorAction SilentlyContinue
    Get-ChildItem $IconDir -Filter '*.ico' -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
    foreach ($i in $cfg.instances) { Update-InstanceShortcut $i }
    Update-PickerShortcut
    Save-Config $cfg
    $made = @($cfg.instances | ForEach-Object { Get-Title $_ }) + 'Claude - choose instance'
    return "Desktop shortcuts ready: $($made -join ', ')."
}

# ---------------------------------------------------------------- picker window

function Show-Picker([string]$SnapshotPath) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName Microsoft.VisualBasic
    [void][ClaudeInstWin]::SetProcessDPIAware()
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $probe = New-Object System.Windows.Forms.Form
    $gr = $probe.CreateGraphics(); $k = $gr.DpiX / 96.0; $gr.Dispose(); $probe.Dispose()
    function Px([double]$v) { [int][Math]::Round($v * $k) }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Claude - choose instance  (Enter or 1-9 opens)'
    $form.AutoScaleMode = 'None'
    $form.StartPosition = 'CenterScreen'
    $form.KeyPreview = $true
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Icon = New-Object System.Drawing.Icon((Join-Path $IconDir 'claude-picker.ico'))

    $list = New-Object System.Windows.Forms.ListView
    $list.Dock = 'Fill'
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.HideSelection = $false
    $list.MultiSelect = $false
    $list.BorderStyle = 'None'
    $images = New-Object System.Windows.Forms.ImageList
    $images.ColorDepth = 'Depth32Bit'
    $images.ImageSize = New-Object System.Drawing.Size((Px 20), (Px 20))
    $list.SmallImageList = $images
    [void]$list.Columns.Add('Instance', (Px 150))
    [void]$list.Columns.Add('Label', (Px 210))
    [void]$list.Columns.Add('Signed in', (Px 72))
    [void]$list.Columns.Add('Window', (Px 70))

    $bar = New-Object System.Windows.Forms.TableLayoutPanel
    $bar.Dock = 'Bottom'
    $bar.Height = Px 40
    $bar.ColumnCount = 5
    $bar.RowCount = 1
    $bar.Padding = New-Object System.Windows.Forms.Padding((Px 6), (Px 6), (Px 6), (Px 6))
    [void]$bar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    foreach ($i in 1..4) { [void]$bar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize'))) }

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = ''
    $hint.ForeColor = [System.Drawing.SystemColors]::GrayText
    $hint.AutoSize = $true
    $hint.Anchor = 'Left'

    function New-Button([string]$Text) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $Text
        $b.AutoSize = $true
        $b.MinimumSize = New-Object System.Drawing.Size((Px 84), (Px 26))
        $b.Margin = New-Object System.Windows.Forms.Padding((Px 4), 0, 0, 0)
        return $b
    }
    $btnNew = New-Button 'New instance'
    $btnLabel = New-Button 'Set label'
    $btnQuit = New-Button 'Quit'
    $btnOpen = New-Button 'Open'
    $tips = New-Object System.Windows.Forms.ToolTip
    $tips.SetToolTip($btnQuit, 'Closes the selected extra instance fully and frees its memory. Its X button only hides it in the tray.')
    $bar.Controls.Add($hint, 0, 0)
    $bar.Controls.Add($btnNew, 1, 0)
    $bar.Controls.Add($btnLabel, 2, 0)
    $bar.Controls.Add($btnQuit, 3, 0)
    $bar.Controls.Add($btnOpen, 4, 0)
    $form.AcceptButton = $btnOpen

    $form.Controls.Add($list)
    $form.Controls.Add($bar)

    $state = @{ cfg = $null; choice = $null }

    $fill = {
        $state.cfg = Read-Config
        $cfg = $state.cfg
        $running = Get-ClaudeAppProcess
        $list.BeginUpdate()
        $list.Items.Clear()
        $images.Images.Clear()

        $images.Images.Add('n1', (New-Object System.Drawing.Icon((Get-IconPath 1), (Px 20), (Px 20))).ToBitmap())
        $main = New-Object System.Windows.Forms.ListViewItem('Claude 1 (normal)', 'n1')
        [void]$main.SubItems.Add($cfg.mainLabel)
        $si = 'No'; if (Test-SignedIn (Get-MainDataDir)) { $si = 'Yes' }
        $op = 'Closed'; if ((Find-ClaudePid $running $null) -gt 0) { $op = 'Open' }
        [void]$main.SubItems.Add($si); [void]$main.SubItems.Add($op)
        $main.Tag = '__main__'
        [void]$list.Items.Add($main)

        foreach ($inst in $cfg.instances) {
            $key = "n$($inst.number)"
            $images.Images.Add($key, (New-Object System.Drawing.Icon((Get-IconPath $inst.number), (Px 20), (Px 20))).ToBitmap())
            $it = New-Object System.Windows.Forms.ListViewItem("Claude $($inst.number)", $key)
            $lab = $inst.label; if (-not $lab) { $lab = '(no label yet)' }
            [void]$it.SubItems.Add($lab)
            $dir = Get-InstanceDir $inst.name
            $si = 'No'; if (Test-SignedIn $dir) { $si = 'Yes' }
            $op = 'Closed'; if ((Find-ClaudePid $running $dir) -gt 0) { $op = 'Open' }
            [void]$it.SubItems.Add($si); [void]$it.SubItems.Add($op)
            $it.Tag = $inst.name
            [void]$list.Items.Add($it)
        }
        $list.EndUpdate()

        $rows = [Math]::Max(3, $list.Items.Count)
        $rowH = [Math]::Max((Px 20), $list.Font.Height) + (Px 6)
        $w = 0; foreach ($c in $list.Columns) { $w += $c.Width }
        $form.ClientSize = New-Object System.Drawing.Size(($w + (Px 4)), ((Px 26) + $rows * $rowH + $bar.Height))
    }

    # Handlers only record the choice and close the picker; Claude is opened after it has closed.
    $openSelected = {
        if ($list.SelectedItems.Count -eq 0) { return }
        $state.choice = [string]$list.SelectedItems[0].Tag
        $form.Close()
    }

    $setLabel = {
        if ($list.SelectedItems.Count -eq 0) { return }
        $tag = [string]$list.SelectedItems[0].Tag
        $cfg = $state.cfg
        if ($tag -eq '__main__') { $current = $cfg.mainLabel; $what = 'Claude 1 (your normal Claude)' }
        else { $inst = Find-Instance $cfg $tag; $current = $inst.label; $what = "Claude $($inst.number)" }
        $new = [Microsoft.VisualBasic.Interaction]::InputBox("Label for $what, for example Work or the account it is signed in to:", 'Set label', $current)
        $new = Get-SafeFileName $new
        if ($new.Length -gt 40) { $new = $new.Substring(0, 40) }
        if ($new -eq $current) { return }
        if ($tag -eq '__main__') { $cfg.mainLabel = $new } else { $inst.label = $new; Update-InstanceShortcut $inst; [void](Write-TitleFile $inst) }
        Save-Config $cfg
        $idx = $list.SelectedIndices[0]
        & $fill
        $list.Items[$idx].Selected = $true
    }

    $newInstance = {
        $cfg = $state.cfg
        $num = Get-NextNumber $cfg
        $instName = "Instance$num"
        while (Test-Path (Get-InstanceDir $instName)) { $num++; $instName = "Instance$num" }
        $lab = [Microsoft.VisualBasic.Interaction]::InputBox("Label for the new Claude $num, for example Work (you can leave it empty):", 'New instance', '')
        $lab = Get-SafeFileName $lab
        if ($lab.Length -gt 40) { $lab = $lab.Substring(0, 40) }
        $inst = [pscustomobject]@{ name = $instName; number = $num; label = $lab; shortcut = '' }
        $cfg.instances += $inst
        Update-InstanceShortcut $inst
        Save-Config $cfg
        $state.choice = $inst.name
        $form.Close()
    }

    # Quit is offered only for an extra instance that is open; your normal Claude has its own menu.
    $updateQuit = {
        $ok = $false
        if ($list.SelectedItems.Count -gt 0) {
            $it = $list.SelectedItems[0]
            $ok = ([string]$it.Tag -ne '__main__') -and ($it.SubItems[3].Text -eq 'Open')
        }
        $btnQuit.Enabled = $ok
    }

    $quitSelected = {
        if ($list.SelectedItems.Count -eq 0) { return }
        $tag = [string]$list.SelectedItems[0].Tag
        if ($tag -eq '__main__') { return }
        $inst = Find-Instance $state.cfg $tag
        $form.UseWaitCursor = $true
        try { $result = Stop-Instance $inst } finally { $form.UseWaitCursor = $false }
        if ($result -eq 'still-open') {
            Show-Message "Claude $($inst.number) did not close. Use the menu at its top left (File, then Exit) to close it." 'Warning'
        }
        $idx = $list.SelectedIndices[0]
        & $fill
        $list.Items[$idx].Selected = $true
        & $updateQuit
    }

    $list.Add_SelectedIndexChanged({ & $updateQuit })
    $btnQuit.Add_Click({ try { & $quitSelected } catch { Show-Message "Could not quit the instance: $($_.Exception.Message)" 'Error' } })
    $list.Add_DoubleClick({ & $openSelected })
    $btnOpen.Add_Click({ & $openSelected })
    $btnLabel.Add_Click({ try { & $setLabel } catch { Show-Message "Could not set the label: $($_.Exception.Message)" 'Error' } })
    $btnNew.Add_Click({ try { & $newInstance } catch { Show-Message "Could not create the instance: $($_.Exception.Message)" 'Error' } })
    $form.Add_KeyDown({
        $e = $_
        if ($e.Modifiers -ne 'None') { return }
        $code = [int]$e.KeyCode
        if ($e.KeyCode -eq 'Escape') { $e.Handled = $true; $form.Close(); return }
        if ($e.KeyCode -eq 'Return') { $e.Handled = $true; $e.SuppressKeyPress = $true; & $openSelected; return }
        $n = -1
        if ($code -ge [int][System.Windows.Forms.Keys]::D1 -and $code -le [int][System.Windows.Forms.Keys]::D9) { $n = $code - [int][System.Windows.Forms.Keys]::D0 }
        if ($code -ge [int][System.Windows.Forms.Keys]::NumPad1 -and $code -le [int][System.Windows.Forms.Keys]::NumPad9) { $n = $code - [int][System.Windows.Forms.Keys]::NumPad0 }
        if ($n -lt 1) { return }
        $e.Handled = $true; $e.SuppressKeyPress = $true
        foreach ($it in $list.Items) {
            $num = 1; if ($it.Tag -ne '__main__') { $num = (Find-Instance $state.cfg ([string]$it.Tag)).number }
            if ($num -eq $n) { $it.Selected = $true; & $openSelected; return }
        }
    })

    & $fill
    # Pre-select the first closed instance, which is usually the one you want next.
    $pick = $null
    foreach ($it in $list.Items) { if ($it.SubItems[3].Text -eq 'Closed') { $pick = $it; break } }
    if (-not $pick) { $pick = $list.Items[0] }
    $pick.Selected = $true; $pick.Focused = $true
    & $updateQuit

    if ($SnapshotPath) {
        # Drawn off-screen, so nothing flashes on the desktop.
        $form.StartPosition = 'Manual'
        $form.Location = New-Object System.Drawing.Point(-32000, -32000)
        $form.ShowInTaskbar = $false
        $form.Show(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 400; [System.Windows.Forms.Application]::DoEvents()
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save($SnapshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose(); $form.Close()
        return
    }
    $form.Add_Shown({ $form.Activate(); $list.Focus() })
    [void]$form.ShowDialog()

    if ($state.choice) {
        try {
            if ($state.choice -eq '__main__') { Open-Main }
            else { Open-Instance (Find-Instance (Read-Config) $state.choice) }
        } catch { Show-Message "Could not open Claude: $($_.Exception.Message)" 'Error' }
    }
}

# ---------------------------------------------------------------- main

# Dot-sourcing this script, as the tests do, only loads the functions above.
if ($MyInvocation.InvocationName -eq '.') { return }

if ($Version) {
    Write-Output "claude-desktop-multi-instance $ToolVersion"
    exit 0
}

if ($List) {
    $cfg = Read-Config
    $running = Get-ClaudeAppProcess
    $rows = @([pscustomobject]@{ No = 1; Name = '(normal Claude)'; Label = $cfg.mainLabel
        SignedIn = (Test-SignedIn (Get-MainDataDir)); Open = ((Find-ClaudePid $running $null) -gt 0); Folder = (Get-MainDataDir) })
    foreach ($i in $cfg.instances) {
        $d = Get-InstanceDir $i.name
        $rows += [pscustomobject]@{ No = $i.number; Name = $i.name; Label = $i.label
            SignedIn = (Test-SignedIn $d); Open = ((Find-ClaudePid $running $d) -gt 0); Folder = $d }
    }
    $rows | Format-Table -AutoSize | Out-String -Width 250
    exit 0
}

New-Item -ItemType Directory -Force -Path $IconDir | Out-Null

if ($Setup) {
    if (-not (Get-ClaudeExe)) { Write-Host $NotInstalled; exit 1 }
    Write-Host (Invoke-Setup)
    exit 0
}

if ($Picker) {
    if (-not (Test-Path (Join-Path $IconDir 'claude-picker.ico'))) { Update-PickerShortcut }
    Show-Picker $Snapshot
    exit 0
}

# Open, label or quit one instance by name.
$cfg = Read-Config
$inst = Find-Instance $cfg $Name
if (-not $inst) {
    if ($Quit) { Write-Host "There is no instance named '$Name'."; exit 1 }
    $inst = [pscustomobject]@{ name = $Name; number = (Get-NextNumber $cfg); label = ''; shortcut = '' }
    $cfg.instances += $inst
    $cfg.instances = @($cfg.instances | Sort-Object number)
}
if ($PSBoundParameters.ContainsKey('Label')) {
    $l = Get-SafeFileName $Label
    if ($l.Length -gt 40) { $l = $l.Substring(0, 40) }
    $inst.label = $l
    Update-InstanceShortcut $inst
    [void](Write-TitleFile $inst)
    Save-Config $cfg
    Write-Host "Claude $($inst.number) is now labelled '$l'."
    exit 0
}
if ($Quit) {
    switch (Stop-Instance $inst) {
        'closed'     { Write-Host "Claude $($inst.number) has quit." }
        'not-open'   { Write-Host "Claude $($inst.number) is not open." }
        'still-open' { Write-Host "Claude $($inst.number) did not close; use its menu (File, then Exit)."; exit 1 }
    }
    exit 0
}
if (-not $inst.shortcut) { Update-InstanceShortcut $inst }
Save-Config $cfg
Open-Instance $inst
