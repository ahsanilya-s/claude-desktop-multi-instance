# Contributing

Thanks for helping. This is a small project with one maintainer, so clear reports and small pull requests help
most. By taking part you agree to follow the [code of conduct](CODE_OF_CONDUCT.md).

## Good ways to help

- **Test reports** from setups the maintainer cannot test:
  - Windows 10
  - Windows on Arm
  - the older Claude installer (`%LOCALAPPDATA%\AnthropicClaude`)
  - non-English Windows

  Open an issue and say what worked and what did not.
- **Bug reports** with the tool version, Claude Desktop version, Windows version and `-List` output. The issue form
  asks for these.
- **Documentation:** unclear steps, mistakes, or a translation of the Quick start.
- **Code:** issues labelled
  [good first issue](https://github.com/ahsanilya-s/claude-desktop-multi-instance/labels/good%20first%20issue) or
  [help wanted](https://github.com/ahsanilya-s/claude-desktop-multi-instance/labels/help%20wanted).

## Development setup

You need Windows 10 or 11, Windows PowerShell 5.1 (built in) and Git. Claude Desktop is only needed to try changes by
hand.

```powershell
git clone https://github.com/ahsanilya-s/claude-desktop-multi-instance.git
cd claude-desktop-multi-instance
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
```

The tests:

- need no modules and no network
- never start Claude
- work in a temporary folder, with `APPDATA`, `LOCALAPPDATA` and the desktop folder pointed there
- build the picker off-screen

CI also runs PSScriptAnalyzer. To run it yourself:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser    # once
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

## Trying changes with Claude Desktop

- Run the script from your clone with a throwaway instance name, so your real instances stay as they are:
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\Open-ClaudeInstance.ps1 -Name Test1`.
  - It keeps its settings next to the script; git ignores them.
  - It makes a desktop shortcut for that instance.
  - Remove the test instance afterwards. The README explains how.
- Never test by quitting or killing your normal Claude. `-Quit` only targets extra instances; keep it that way.
- To redraw the README screenshot, run `powershell -NoProfile -ExecutionPolicy Bypass -File tools\New-Screenshot.ps1`.
  It draws the picker off-screen with sample data and placeholder icons.

## Guidelines

- **Windows PowerShell 5.1:** no external modules, and no compiled binaries in the repository. The title helper is
  compiled from source when it is first needed.
- **ASCII only** in `.ps1` and `.psd1` files, because Windows PowerShell reads UTF-8 files without a BOM as ANSI. The
  tests check this.
- **One file for users:** `Open-ClaudeInstance.ps1` stays self-contained.
- **No Anthropic artwork** in the repository. The icons come from the user's installed app at run time.
- **The picker is a work tool.** Keep it compact, with the list taking most of the window. No banners or large
  headings.
- **Comments** stay short and explain why.
- **Tests and docs:** add or update a test when behaviour changes. When users will notice a change, update
  `README.md` and the `Unreleased` part of `CHANGELOG.md`.

## Pull requests

Keep each pull request to one topic, and say what you tested; the template has a checklist. By contributing, you agree
that your contribution is licensed under the project's [MIT licence](LICENSE).

## Releasing (maintainers)

1. Set `$ToolVersion` in `Open-ClaudeInstance.ps1`. In `CHANGELOG.md`, move the `Unreleased` items into a new
   version section and add its link at the bottom.
2. Commit, then tag and push the tag: `git tag -a v0.2.0 -m "v0.2.0"`, then `git push origin v0.2.0`.
3. The Release workflow then:
   - runs the tests
   - builds `claude-desktop-multi-instance.zip`, `SHA256SUMS.txt` and the release notes with
     `tools\Build-Release.ps1`
   - publishes the GitHub release
