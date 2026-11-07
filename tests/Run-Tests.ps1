<#
    Test suite for Open-ClaudeInstance.ps1. Run it in its own Windows PowerShell 5.1 process:

        powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1

    It needs no modules, no network and no Claude Desktop. Everything happens in a temporary folder:
    APPDATA, LOCALAPPDATA and the desktop folder point there while the tests run, Claude Desktop is
    stubbed out, and the picker is built off-screen and never shown. Exit code 0 means every test passed.
#>
param(
    # Skip the picker tests, which need a Windows desktop session.
    [switch]$SkipGui
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceScript = Join-Path $repoRoot 'Open-ClaudeInstance.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) ('cdmi-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$savedEnv = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA }
$outcomes = New-Object System.Collections.ArrayList

function Test-Case([string]$Title, [scriptblock]$Body) {
    try {
        & $Body
        [void]$outcomes.Add($true)
        Write-Host "  ok    $Title"
    } catch {
        [void]$outcomes.Add($false)
        Write-Host "  FAIL  $Title" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Equal($Expected, $Actual, [string]$What) {
    if ($Expected -ne $Actual) { throw "${What}: expected '$Expected' but got '$Actual'" }
}

function Assert-True($Condition, [string]$What) {
    if (-not $Condition) { throw "expected $What" }
}

function Get-SourceFile {
    Get-ChildItem $repoRoot -Recurse -File -Include *.ps1, *.psd1 |
        Where-Object { $_.FullName -notmatch '\\(dist|\.git)\\' }
}

New-Item -ItemType Directory -Path $work | Out-Null
try {
    Write-Host "Open-ClaudeInstance.ps1 tests, Windows PowerShell $($PSVersionTable.PSVersion)"

    # ------------------------------------------------------------ static checks

    Test-Case 'every PowerShell file parses without errors' {
        foreach ($f in Get-SourceFile) {
            $tokens = $null; $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$parseErrors)
            Assert-Equal 0 @($parseErrors).Count "parse errors in $($f.Name)"
        }
    }

    Test-Case 'source files are plain ASCII (Windows PowerShell misreads UTF-8 without a BOM)' {
        foreach ($f in Get-SourceFile) {
            $bad = 0
            foreach ($b in [IO.File]::ReadAllBytes($f.FullName)) { if ($b -gt 127) { $bad++ } }
            Assert-Equal 0 $bad "non-ASCII bytes in $($f.Name)"
        }
    }

    Test-Case 'the script contains no personal paths' {
        Assert-True ((Get-Content $sourceScript -Raw) -notmatch '(?i)C:\\Users\\[^<%$]') 'no C:\Users\<name> paths'
    }

    Test-Case 'Get-Help shows the synopsis, parameters and examples' {
        $help = Get-Help $sourceScript -Full
        Assert-True ($help.Synopsis -match 'Claude Desktop') 'a synopsis that mentions Claude Desktop'
        Assert-True (@($help.examples.example).Count -ge 4) 'at least 4 examples'
        foreach ($p in 'Name', 'Label', 'Picker', 'List', 'Setup', 'Quit', 'Version') {
            Assert-True (@($help.parameters.parameter | Where-Object { $_.name -eq $p }).Count -eq 1) "help for -$p"
        }
    }

    Test-Case 'CHANGELOG has an entry for the script version' {
        $scriptVersion = [regex]::Match((Get-Content $sourceScript -Raw), "\`$ToolVersion = '([^']+)'").Groups[1].Value
        Assert-True ($scriptVersion -match '^\d+\.\d+\.\d+$') "a version number, got '$scriptVersion'"
        $changelog = Get-Content (Join-Path $repoRoot 'CHANGELOG.md') -Raw
        Assert-True ($changelog -match "(?m)^## \[$([regex]::Escape($scriptVersion))\]") "a CHANGELOG section for $scriptVersion"
    }

    # ------------------------------------------------------------ the script as a command

    $toolDir = Join-Path $work 'tool'
    New-Item -ItemType Directory -Path $toolDir | Out-Null
    Copy-Item $sourceScript $toolDir
    $toolScript = Join-Path $toolDir 'Open-ClaudeInstance.ps1'

    # A sandbox Windows profile: from here on the tool sees these folders instead of yours.
    $env:APPDATA = Join-Path $work 'Roaming'
    $env:LOCALAPPDATA = Join-Path $work 'Local'
    New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null

    Test-Case '-Version prints the version and creates no files' {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $toolScript -Version
        Assert-Equal 0 $LASTEXITCODE 'exit code'
        Assert-True ("$out" -match '^claude-desktop-multi-instance \d+\.\d+\.\d+$') "a version line, got '$out'"
        Assert-Equal 1 @(Get-ChildItem $toolDir).Count 'files in the tool folder'
    }

    Test-Case '-List works with no extra instances' {
        $out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $toolScript -List) -join "`n"
        Assert-Equal 0 $LASTEXITCODE 'exit code'
        Assert-True ($out -match '\(normal Claude\)') 'a row for the normal Claude'
        Assert-Equal 1 @(Get-ChildItem $toolDir).Count 'files in the tool folder'
    }

    Test-Case 'instance names are limited to letters, digits and dashes' {
        $ErrorActionPreference = 'Continue'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $toolScript -Name 'bad name!' -List 2>&1 | Out-Null
        Assert-True ($LASTEXITCODE -ne 0) 'a non-zero exit code for "bad name!"'
    }

    # ------------------------------------------------------------ functions, with Claude Desktop stubbed out

    . $toolScript
    function Get-ClaudePackage { $null }   # pretend Claude Desktop is not installed,
    function Get-ClaudeExe { $null }       # so nothing on this PC is opened or copied
    $desktop = Join-Path $work 'Desktop'
    New-Item -ItemType Directory -Path $desktop | Out-Null
    function Get-ShortcutDir { $desktop }

    Test-Case 'dot-sourcing loads the functions and runs nothing' {
        foreach ($fn in 'Read-Config', 'Save-Config', 'Invoke-Setup', 'Show-Picker', 'Open-Instance', 'Stop-Instance', 'New-BadgeIcon') {
            Assert-True (Get-Command $fn -CommandType Function -ErrorAction SilentlyContinue) "function $fn"
        }
        Assert-Equal $toolDir $Base 'the folder the tool keeps its files in'
        Assert-Equal 1 @(Get-ChildItem $toolDir).Count 'files in the tool folder'
    }

    Test-Case 'titles, colours and file names' {
        Assert-Equal 'Claude 2' (Get-Title ([pscustomobject]@{ number = 2; label = '' })) 'title without a label'
        Assert-Equal 'Claude 3 - Work' (Get-Title ([pscustomobject]@{ number = 3; label = 'Work' })) 'title with a label'
        Assert-Equal '#2563EB' (Get-Color 2) 'colour of Claude 2'
        Assert-Equal '#DC2626' (Get-Color 9) 'colour of Claude 9'
        Assert-Equal '#2563EB' (Get-Color 10) 'colour of Claude 10 (colours repeat after eight)'
        Assert-Equal 'ab c' (Get-SafeFileName ' a/b:*?"<>| c ') 'name with characters Windows does not allow'
    }

    Test-Case 'Find-ClaudePid tells the normal Claude and each instance apart' {
        $dir2 = Get-InstanceDir 'Instance2'
        $procs = @(
            [pscustomobject]@{ ProcessId = 30; CreationDate = (Get-Date).AddMinutes(-1); CommandLine = "`"C:\App\claude.exe`" --user-data-dir=`"$dir2`"" }
            [pscustomobject]@{ ProcessId = 10; CreationDate = (Get-Date).AddMinutes(-9); CommandLine = '"C:\App\claude.exe"' }
            [pscustomobject]@{ ProcessId = 20; CreationDate = (Get-Date).AddMinutes(-5); CommandLine = "`"C:\App\claude.exe`" --user-data-dir=`"$($dir2.ToUpper())`"" }
        )
        Assert-Equal 10 (Find-ClaudePid $procs $null) 'normal Claude'
        Assert-Equal 20 (Find-ClaudePid $procs $dir2) 'Claude 2 (the oldest copy wins; case does not matter)'
        Assert-Equal 0 (Find-ClaudePid $procs (Get-InstanceDir 'Instance3')) 'Claude 3, which is not running'
        Assert-Equal 0 (Find-ClaudePid @() $null) 'nothing running'
    }

    Test-Case 'Test-SignedIn looks only for the token cache key' {
        $d = Join-Path $work 'signin'
        New-Item -ItemType Directory -Path $d | Out-Null
        Assert-Equal $false (Test-SignedIn $d) 'no config.json'
        Set-Content (Join-Path $d 'config.json') '{"locale":"en-US"}'
        Assert-Equal $false (Test-SignedIn $d) 'signed out'
        Set-Content (Join-Path $d 'config.json') '{"locale":"en-US","oauth:tokenCacheV2":"..."}'
        Assert-Equal $true (Test-SignedIn $d) 'signed in'
    }

    Test-Case 'first -Setup prepares Claude 2 and both desktop shortcuts' {
        $message = Invoke-Setup
        Assert-Equal 'Desktop shortcuts ready: Claude 2, Claude - choose instance.' $message 'message'
        Assert-True (Test-Path (Join-Path $desktop 'Claude 2.lnk')) 'shortcut "Claude 2"'
        Assert-True (Test-Path (Join-Path $desktop 'Claude - choose instance.lnk')) 'shortcut "Claude - choose instance"'
        $saved = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        Assert-Equal 'Instance2' (@($saved.instances)[0].name) 'instance saved in instances.json'
        Assert-Equal "$(Join-Path $desktop 'Claude 2.lnk')" (@($saved.instances)[0].shortcut) 'shortcut path saved'
        # Clean up for the tests below.
        Remove-Item $ConfigPath
        Get-ChildItem $desktop | Remove-Item
    }

    Test-Case 'badge icons are valid multi-size .ico files' {
        # A stand-in for the Claude icon, so no Anthropic artwork is needed.
        $bmp = New-Object System.Drawing.Bitmap(256, 256)
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::FromArgb(255, 240, 140, 40)); $g.Dispose()
        $bmp.Save($BasePng, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        $ico = Join-Path $work 'badge-2.ico'
        New-BadgeIcon '2' (Get-Color 2) $ico
        $bytes = [IO.File]::ReadAllBytes($ico)
        Assert-Equal 1 ([BitConverter]::ToUInt16($bytes, 2)) 'icon type'
        Assert-Equal 8 ([BitConverter]::ToUInt16($bytes, 4)) 'number of sizes'
        $sizes = foreach ($i in 0..7) { $w = $bytes[6 + 16 * $i]; if ($w -eq 0) { 256 } else { $w } }
        Assert-Equal '16,20,24,32,40,48,64,256' ($sizes -join ',') 'sizes'
        $icon = New-Object System.Drawing.Icon($ico, 32, 32)
        $pic = $icon.ToBitmap()
        Assert-Equal 32 $pic.Width 'width of the 32 px picture'
        $corner = $pic.GetPixel(2, 2); $badge = $pic.GetPixel(16, 22)
        Assert-True ($corner.R -gt 200 -and $corner.B -lt 100) "the base picture in the top-left corner, got $corner"
        Assert-True ($badge.B -gt 150 -and $badge.R -lt 120) "the blue badge at the bottom right, got $badge"
        $pic.Dispose(); $icon.Dispose()
        $plain = Join-Path $work 'plain.ico'
        New-BadgeIcon '' '' $plain
        $pic = (New-Object System.Drawing.Icon($plain, 32, 32)).ToBitmap()
        $c = $pic.GetPixel(16, 22)
        Assert-True ($c.R -gt 200 -and $c.B -lt 100) "no badge on Claude 1's icon, got $c"
        $pic.Dispose()
    }

    Test-Case 'icons still work when Claude Desktop is missing' {
        Remove-Item $BasePng
        $ico = Join-Path $work 'fallback.ico'
        New-BadgeIcon '3' (Get-Color 3) $ico
        Assert-True ((Get-Item $ico).Length -gt 1000) 'an icon file'
        Assert-True (-not (Test-Path $BasePng)) 'the stand-in picture is not saved'
    }

    Test-Case 'Read-Config finds instance folders and numbers them' {
        foreach ($n in 'Instance3', 'Work', 'NotAProfile') { New-Item -ItemType Directory -Force -Path (Get-InstanceDir $n) | Out-Null }
        Set-Content (Join-Path (Get-InstanceDir 'Instance3') 'Local State') '{}'
        Set-Content (Join-Path (Get-InstanceDir 'Work') 'Local State') '{}'
        $cfg = Read-Config
        Assert-Equal 'Main' $cfg.mainLabel 'label of the normal Claude'
        Assert-Equal 'Instance3,Work' ((@($cfg.instances) | ForEach-Object { $_.name }) -join ',') 'instances found'
        Assert-Equal '3,4' ((@($cfg.instances) | ForEach-Object { $_.number }) -join ',') 'numbers'
        Assert-Equal 5 (Get-NextNumber $cfg) 'next free number'
    }

    Test-Case 'labels and numbers survive a save and reload' {
        $cfg = Read-Config
        (Find-Instance $cfg 'Work').label = 'Client A'
        $cfg.mainLabel = 'Personal'
        Save-Config $cfg
        $again = Read-Config
        Assert-Equal 'Client A' (Find-Instance $again 'Work').label 'label'
        Assert-Equal 4 (Find-Instance $again 'Work').number 'number'
        Assert-Equal 'Personal' $again.mainLabel 'label of the normal Claude'
    }

    Test-Case 'a damaged instances.json does not stop the tool' {
        $good = Get-Content $ConfigPath -Raw
        Set-Content $ConfigPath '{ this is not JSON'
        $cfg = Read-Config
        Assert-Equal 'Main' $cfg.mainLabel 'default label'
        Assert-Equal 2 @($cfg.instances).Count 'instances found again from their folders'
        Set-Content $ConfigPath $good
    }

    Test-Case 'instance shortcuts open the right instance and follow label changes' {
        $inst = [pscustomobject]@{ name = 'Work'; number = 4; label = 'Client A'; shortcut = '' }
        Update-InstanceShortcut $inst
        $link = Join-Path $desktop 'Claude 4 - Client A.lnk'
        Assert-True (Test-Path $link) 'shortcut "Claude 4 - Client A"'
        $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
        Assert-True ($lnk.TargetPath -like '*\WindowsPowerShell\v1.0\powershell.exe') "Windows PowerShell as the target, got $($lnk.TargetPath)"
        Assert-True ($lnk.Arguments -like "*-ExecutionPolicy Bypass -File `"$ScriptPath`" -Name Work") "arguments, got $($lnk.Arguments)"
        Assert-True ($lnk.IconLocation -like '*\icons\claude-4.ico,0') "icon, got $($lnk.IconLocation)"
        $inst.label = ''
        Update-InstanceShortcut $inst
        Assert-True (Test-Path (Join-Path $desktop 'Claude 4.lnk')) 'shortcut renamed to "Claude 4"'
        Assert-True (-not (Test-Path $link)) 'old shortcut removed'
    }

    Test-Case 'the picker shortcut opens the picker' {
        Update-PickerShortcut
        $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Claude - choose instance.lnk'))
        Assert-True ($lnk.Arguments -like "*-File `"$ScriptPath`" -Picker") "arguments, got $($lnk.Arguments)"
        Assert-True (Test-Path (Join-Path $IconDir 'claude-picker.ico')) 'the picker icon'
    }

    Test-Case 'title files hold the window title, without a byte order mark' {
        $file = Write-TitleFile ([pscustomobject]@{ name = 'Work'; number = 4; label = 'Client A' })
        Assert-Equal 'Claude 4 - Client A' ([IO.File]::ReadAllText($file)) 'title'
        Assert-True ([IO.File]::ReadAllBytes($file)[0] -ne 0xEF) 'no byte order mark'
    }

    Test-Case 'the title helper compiles and exits cleanly' {
        $exe = Get-KeeperExe
        Assert-True (Test-Path $exe) 'the helper program'
        $p = Start-Process $exe -ArgumentList 'x' -PassThru -Wait
        Assert-Equal 2 $p.ExitCode 'exit code when arguments are missing'
        $p = Start-Process $exe -ArgumentList '999999', "`"$work\none.txt`"", '"Claude 9"' -PassThru -Wait
        Assert-Equal 0 $p.ExitCode 'exit code when the Claude process is gone'
    }

    # ------------------------------------------------------------ picker, built off-screen

    if ($SkipGui -or -not [Environment]::UserInteractive) {
        Write-Host '  skip  picker tests (no desktop session)'
    } else {
        # Same picker, except that a test hook drives it instead of ShowDialog().
        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($toolScript, [ref]$tokens, [ref]$parseErrors)
        $pickerAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-Picker' }, $true)
        $patched = $pickerAst.Extent.Text.Replace('[void]$form.ShowDialog()', 'Invoke-PickerTestHook $form $list $btnQuit')
        if ($patched -eq $pickerAst.Extent.Text) { throw 'The ShowDialog() call was not found in Show-Picker.' }
        . ([scriptblock]::Create($patched))

        # Drives the picker: selects a row, clicks Quit or presses keys, as the test asks, and records what it saw.
        function Invoke-PickerTestHook($PickerForm, $PickerList, $QuitButton) {
            $null = $PickerForm.Handle; $null = $PickerList.Handle
            $script:Seen = @{
                rows     = @($PickerList.Items | ForEach-Object { '{0}|{1}|{2}' -f $_.Text, $_.SubItems[1].Text, $_.SubItems[3].Text })
                selected = $PickerList.SelectedItems[0].Text
            }
            if ($null -ne $script:SelectRow) {
                $PickerList.Items[$script:SelectRow].Selected = $true
                $script:Seen.quitEnabled = $QuitButton.Enabled
            }
            if ($script:ClickQuit) {
                $click = $QuitButton.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic')
                [void]$click.Invoke($QuitButton, [object[]]@([EventArgs]::Empty))
            }
            $onKey = [System.Windows.Forms.Control].GetMethod('OnKeyDown', [Reflection.BindingFlags]'Instance,NonPublic')
            foreach ($keyName in $script:Keys) {
                if ($PickerForm.IsDisposed) { break }
                [void]$onKey.Invoke($PickerForm, [object[]]@([System.Windows.Forms.KeyEventArgs]::new([System.Windows.Forms.Keys]$keyName)))
            }
            $script:Seen.closed = $PickerForm.IsDisposed
            if (-not $PickerForm.IsDisposed) { $PickerForm.Dispose() }
        }

        $script:Calls = New-Object System.Collections.ArrayList
        $script:Running = @()
        function Get-ClaudeAppProcess { $script:Running }
        function Open-Instance($Inst) { [void]$script:Calls.Add("open Claude $($Inst.number)") }
        function Open-Main { [void]$script:Calls.Add('open Claude 1') }
        function Stop-Instance($Inst) { [void]$script:Calls.Add("quit Claude $($Inst.number)"); 'closed' }
        function Show-Message($Text) { [void]$script:Calls.Add("message: $Text") }

        function Invoke-TestPicker([string[]]$Keys, $SelectRow = $null, [switch]$ClickQuit, $Running = @()) {
            $script:Calls.Clear()
            $script:Keys = $Keys
            $script:SelectRow = $SelectRow
            $script:ClickQuit = [bool]$ClickQuit
            $script:Running = $Running
            Show-Picker $null
        }

        $instance3Running = [pscustomobject]@{ ProcessId = 3; CreationDate = (Get-Date); CommandLine = "claude.exe --user-data-dir=`"$(Get-InstanceDir 'Instance3')`"" }
        $mainRunning = [pscustomobject]@{ ProcessId = 1; CreationDate = (Get-Date); CommandLine = 'claude.exe' }

        Test-Case 'picker lists the normal Claude and every instance' {
            Invoke-TestPicker @()
            Assert-Equal 'Claude 1 (normal)|Personal|Closed;Claude 3|(no label yet)|Closed;Claude 4|Client A|Closed' ($script:Seen.rows -join ';') 'rows'
        }

        Test-Case 'picker: a number key opens that instance' {
            Invoke-TestPicker @('D3')
            Assert-Equal 'open Claude 3' ($script:Calls -join '; ') 'what was opened'
            Assert-True $script:Seen.closed 'the picker closed'
        }

        Test-Case 'picker: number pad keys work too' {
            Invoke-TestPicker @('NumPad4')
            Assert-Equal 'open Claude 4' ($script:Calls -join '; ') 'what was opened'
        }

        Test-Case 'picker: Enter opens the selected row, which starts on the first closed one' {
            Invoke-TestPicker @('Return') -Running @($mainRunning, $instance3Running)
            Assert-Equal 'Claude 4' $script:Seen.selected 'the row selected at the start'
            Assert-Equal 'open Claude 4' ($script:Calls -join '; ') 'what was opened'
        }

        Test-Case 'picker: Esc and unused numbers open nothing' {
            Invoke-TestPicker @('D9')
            Assert-Equal '' ($script:Calls -join '; ') 'what was opened after 9'
            Assert-True (-not $script:Seen.closed) 'the picker stays open after 9'
            Invoke-TestPicker @('Escape')
            Assert-Equal '' ($script:Calls -join '; ') 'what was opened after Esc'
            Assert-True $script:Seen.closed 'the picker closed after Esc'
        }

        Test-Case 'picker: Quit is offered only for an open extra instance' {
            Invoke-TestPicker @() -SelectRow 1 -Running @($mainRunning, $instance3Running)
            Assert-True $script:Seen.quitEnabled 'Quit enabled for Claude 3, which is open'
            Invoke-TestPicker @() -SelectRow 0 -Running @($mainRunning, $instance3Running)
            Assert-True (-not $script:Seen.quitEnabled) 'Quit disabled for the normal Claude'
            Invoke-TestPicker @() -SelectRow 2 -Running @($mainRunning, $instance3Running)
            Assert-True (-not $script:Seen.quitEnabled) 'Quit disabled for Claude 4, which is closed'
        }

        Test-Case 'picker: Quit asks the selected instance to quit' {
            Invoke-TestPicker @() -SelectRow 1 -ClickQuit -Running @($mainRunning, $instance3Running)
            Assert-Equal 'quit Claude 3' ($script:Calls -join '; ') 'what was asked to quit'
        }

        Test-Case 'picker: -Snapshot saves a picture without showing the picker on screen' {
            $png = Join-Path $work 'picker.png'
            Show-Picker $png
            $img = [System.Drawing.Image]::FromFile($png)
            Assert-True ($img.Width -gt 300 -and $img.Height -gt 100) "a picture of the picker, got $($img.Width)x$($img.Height)"
            $img.Dispose()
        }
    }
} finally {
    $env:APPDATA = $savedEnv.APPDATA
    $env:LOCALAPPDATA = $savedEnv.LOCALAPPDATA
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

$failed = @($outcomes | Where-Object { -not $_ }).Count
Write-Host ''
Write-Host "$($outcomes.Count - $failed) passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
