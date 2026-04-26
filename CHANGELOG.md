# Changelog

All notable changes are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project does not yet follow strict SemVer because it is pre-1.0.

## [Unreleased]

### Added
- PR template, bug and feature issue templates.
- CHANGELOG.md.
- README badge for CI.

### Changed
- (Reserved for upcoming items.)

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
