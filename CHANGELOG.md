# Changelog

All notable changes are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project does not yet follow strict SemVer because it is pre-1.0.

## [Unreleased]

### Added
- `setup.sh` — single curl-pipe-bash install entry point. Detects the latest release, fetches the tarball, places framework files under `$XDG_DATA_HOME/claudetoggle`, installs the CLI to `$PREFIX/bin/claudetoggle`, wires the dispatcher into `settings.json`. `--local` mode for development from a clone.
- `bin/claudetoggle` — bash CLI with subcommands `add`, `remove`, `list`, `on`, `off`, `update`, `uninstall`, `doctor`, `help`.
- PR template, bug and feature issue templates.
- CHANGELOG.md, README badges, GitHub repo description and topics.

### Changed
- **Layout migrated to XDG Base Directory.** Data home is now `$XDG_DATA_HOME/claudetoggle/` (default `~/.local/share/claudetoggle/`) instead of `~/.claude/toggles/`. State sits under `<data>/state/` (no dot prefix). Debug log is `<data>/debug.log`. macOS works the same way via the XDG fallback.
- **Install model is now CLI-driven.** `./install.sh` and the per-toggle directory dropping pattern are removed. Use `claudetoggle add <name|path>` to register; `claudetoggle remove <name>` to unregister.
- **Permissions deny pattern** is now `*claudetoggle/state/<name>/*`. Single substring glob works regardless of `$XDG_DATA_HOME` overrides.
- **Peer-script lib resolution idiom** is now `${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "$0")")/../../lib}` — two `..` because peer scripts live at `<data>/toggles/<name>/<peer>.sh`.
- `uninstall.sh` is now a thin wrapper that forwards to `claudetoggle uninstall`.

### Notes
- The CLI is bash for v0.1.0. A native binary rewrite (Go) is planned for v0.2.0; the surface won't change.

## [0.1.0] — 2026-04-26

First public-ready cut.

### Added
- Registry layout: one directory per toggle at `~/.claude/toggles/<name>/`, declaring metadata in `toggle.sh`.
- Generic dispatcher (`bin/dispatch.sh`) for `UserPromptSubmit` and `SessionStart`.
- Statusline snippet (`bin/statusline.sh`) exposing `claudetoggle_statusline`.
- `install.sh` and `uninstall.sh`. Idempotent merge into `~/.claude/settings.json`. State preserved by default.
- `lib/`: `scope.sh`, `command_call.sh`, `hook_io.sh`, `toggle.sh`.
- Reference toggles under `examples/`: `coauth` (project-scope, peer enforcement script) and `devlog` (session-scope, silent, custom statusline fragment).
- `TOGGLE_API` schema version field.
- Per-toggle `permissions.deny` rules templated into settings.json.
- Single shared reannounce counter per toggle (no per-session split).
- 93 bats cases. `make lint`, `make fmt-check`, `make test`, `make check` targets. Pre-commit and pre-push git hooks (installed via `make hooks`). GitHub Actions CI.
- Branch protection on `main`: PR-only, squash merge, required CI checks, no bypass.
