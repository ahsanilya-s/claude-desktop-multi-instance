# Changelog

All notable changes to this project are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-07

First public release.

### Added

- Open extra Claude Desktop instances on Windows. Each has its own data folder (`%APPDATA%\Claude-<Name>`), sign-in,
  settings and MCP servers.
- Numbered desktop shortcuts with badged icons. The icons are made on your PC from your installed Claude icon.
- Window titles such as "Claude 2 - Work", kept by a small helper (about 2 MB of memory). The helper is compiled
  from source on first use.
- Picker window. It lists every instance with its label, sign-in state and window state.
  - Keys 1-9 and Enter open an instance; Esc closes the picker.
  - Buttons: New instance, Set label, Quit and Open.
- `-Quit` and the picker's Quit button close an extra instance properly, the way Windows closes apps at sign-out.
  The window's X only hides it in the tray.
- `-Setup` creates the "Claude 2" and "Claude - choose instance" shortcuts on the first run, and rebuilds icons and
  shortcuts later.
- `-List`, `-Label`, `-Version`, and built-in help (`Get-Help .\Open-ClaudeInstance.ps1 -Full`).
- Test suite that needs no modules, no network and no Claude Desktop. PSScriptAnalyzer and CI run on GitHub Actions.

[Unreleased]: https://github.com/ahsanilya-s/claude-desktop-multi-instance/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ahsanilya-s/claude-desktop-multi-instance/releases/tag/v0.1.0
