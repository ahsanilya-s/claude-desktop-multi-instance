<#
    Builds the release files into dist\:

        claude-desktop-multi-instance.zip   Open-ClaudeInstance.ps1, README.md, LICENSE, CHANGELOG.md
        SHA256SUMS.txt                      SHA-256 checksum of the zip
        RELEASE_NOTES.md                    this version's CHANGELOG section plus install steps

    Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Release.ps1 [-Tag v1.2.3]
    With -Tag, the build stops if the tag does not match $ToolVersion in the script.
#>
param([string]$Tag)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$repoUrl = 'https://github.com/ahsanilya-s/claude-desktop-multi-instance'
$zipName = 'claude-desktop-multi-instance.zip'

$source = Get-Content (Join-Path $repoRoot 'Open-ClaudeInstance.ps1') -Raw
$found = [regex]::Match($source, "\`$ToolVersion = '([^']+)'")
if (-not $found.Success) { throw 'No $ToolVersion line found in Open-ClaudeInstance.ps1.' }
$ver = $found.Groups[1].Value
if ($Tag -and $Tag -ne "v$ver") { throw "Tag '$Tag' does not match the script version $ver (expected v$ver)." }

$changelog = Get-Content (Join-Path $repoRoot 'CHANGELOG.md') -Raw
$section = [regex]::Match($changelog, "(?ms)^## \[$([regex]::Escape($ver))\][^\r\n]*\r?\n(.*?)(?=^## \[|^\[[^\]]+\]: |\z)")
if (-not $section.Success) { throw "CHANGELOG.md has no section for $ver." }

$dist = Join-Path $repoRoot 'dist'
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
$stage = Join-Path $dist 'stage'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($f in 'Open-ClaudeInstance.ps1', 'README.md', 'LICENSE', 'CHANGELOG.md') {
    Copy-Item (Join-Path $repoRoot $f) $stage
}
$zip = Join-Path $dist $zipName
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
Remove-Item $stage -Recurse -Force

$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $dist 'SHA256SUMS.txt'), "$hash  $zipName`n", $utf8)

$notes = @"
$($section.Groups[1].Value.Trim())

### Install or update

You need Windows 10 or 11 and [Claude Desktop](https://claude.ai/download). In PowerShell:

``````powershell
`$dir = "`$env:USERPROFILE\ClaudeInstances"
`$zip = "`$env:TEMP\$zipName"
Invoke-WebRequest -UseBasicParsing $repoUrl/releases/download/v$ver/$zipName -OutFile `$zip
Expand-Archive `$zip `$dir -Force
Unblock-File "`$dir\Open-ClaudeInstance.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "`$dir\Open-ClaudeInstance.ps1" -Setup
``````

Updating keeps your instances, labels and sign-ins. Full guide: [README]($repoUrl#readme).

SHA-256 of ``$zipName``: ``$hash``

Unofficial community tool, not made or endorsed by Anthropic.
"@
[IO.File]::WriteAllText((Join-Path $dist 'RELEASE_NOTES.md'), $notes.Replace("`r`n", "`n"), $utf8)

Write-Host "Built claude-desktop-multi-instance $ver"
Get-ChildItem $dist | ForEach-Object { Write-Host ('  {0,-36} {1,8} bytes' -f $_.Name, $_.Length) }
Write-Host "  SHA-256 $hash"
