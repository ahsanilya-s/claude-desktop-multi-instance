# Security policy

## Supported versions

Only the [latest release](https://github.com/ahsanilya-s/claude-desktop-multi-instance/releases/latest) gets fixes.

## Reporting a vulnerability

Please report security problems privately. Do not open a public issue.

- Use **[Report a vulnerability](https://github.com/ahsanilya-s/claude-desktop-multi-instance/security/advisories/new)**.
  Only the maintainer can see the report.
- Include what you found, how to reproduce it, and which version you used.

This is a small volunteer project, so replies are best effort. Once a fix is released, you will be credited in the
release notes unless you would rather not be.

Problems in Claude Desktop itself go to Anthropic, under its
[responsible disclosure policy](https://www.anthropic.com/responsible-disclosure-policy).

## What the tool does on your PC

This list is for anyone reviewing the script, `Open-ClaudeInstance.ps1`.

**How it runs**

- It runs as you, without admin rights, and makes no network requests.
- It starts the Claude Desktop you installed with `--user-data-dir="%APPDATA%\Claude-<Name>"`. It does not patch,
  inject into or copy the app.

**What it writes**

- Its own folder, the one you installed it to: `instances.json`, `icons\`, `titles\`, `bin\`, `claude-256.png`.
- Desktop shortcuts it names `Claude N….lnk` and `Claude - choose instance.lnk`.
- New folders named `%APPDATA%\Claude-<Name>`.

**What it reads**

- It reads an instance's `config.json` only to check whether the token cache key is present, for the "Signed in"
  column. It never reads out, copies or sends the token.
- It lists running `claude.exe` processes and their command lines, to find which instance is open.

**What it runs**

- It compiles a small title helper from the C# source inside the script, using the .NET Framework compiler
  (`Add-Type`). The helper renames that instance's window and exits with it. No prebuilt programs are shipped.
- The shortcuts start Windows PowerShell with `-ExecutionPolicy Bypass` for that one process. Your system's execution
  policy is not changed.
- Quit sends the instance's windows the standard Windows end-session messages: `WM_QUERYENDSESSION`, then
  `WM_ENDSESSION`, with `ENDSESSION_CLOSEAPP`. Claude then closes itself. The tool never force-kills a process, and
  it never quits your normal Claude.
