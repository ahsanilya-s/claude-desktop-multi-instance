# Notes for coding agents

- **The tool** is one file, `Open-ClaudeInstance.ps1`, for Windows PowerShell 5.1. `tests\Run-Tests.ps1` holds the
  tests, `tools\` the release and screenshot scripts, and `docs\` the GitHub Pages site.
- **Run the tests** with `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1`.
  - They need no network, no modules and no Claude Desktop.
  - They work in a temporary folder and build the picker off-screen.
- **Never quit, kill or restart the user's normal Claude Desktop.** You may be running inside it. `-Quit` only targets
  extra instances (processes started with `--user-data-dir`); keep it that way.
- **Do not drive the user's screen** (SendKeys, clicks) to test the picker. Use the off-screen tests.
- **Keep the code portable:**
  - ASCII only and PowerShell 5.1 syntax
  - no external modules
  - no binaries or Anthropic logos in the repository; icons are generated at run time from the installed app
- **Keep the picker compact.** The list gets most of the window.
- **For user-visible changes,** update `README.md`, `docs\` and the `Unreleased` part of `CHANGELOG.md`.
