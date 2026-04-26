# Changelog

All notable changes are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project does not yet follow strict SemVer because it is pre-1.0 — minor bumps may include breaking changes, and the changelog calls them out explicitly.

## [Unreleased]

(Reserved.)

## [0.1.0] — 2026-04-26

First public-ready cut.

### Install

```sh
curl -sSfL https://raw.githubusercontent.com/spuddydev/claudetoggle/main/setup.sh | sh
```

### Added

- `setup.sh` — single curl-pipe-bash install entry point. Detects the latest release, fetches the tarball, places framework files under `$XDG_DATA_HOME/claudetoggle/`, installs the CLI to `$PREFIX/bin/claudetoggle`, wires the dispatcher into `settings.json`. `--local` mode for development from a clone.
- `bin/claudetoggle` — bash CLI with subcommands `add`, `remove`, `list`, `on`, `off`, `update`, `uninstall`, `doctor`, `help`.
- Registry layout under `$XDG_DATA_HOME/claudetoggle/toggles/<name>/`; one directory per toggle declaring metadata in `toggle.sh`.
- Generic dispatcher (`bin/dispatch.sh`) for `UserPromptSubmit` and `SessionStart`. Cheap pre-filter, locale-stable iteration, per-toggle `TOGGLE_API` schema version, three-code `toggle_active` (on / off / scope-unavailable), single shared reannounce counter per toggle.
- Statusline snippet (`bin/statusline.sh`) exposing `claudetoggle_statusline`. Empty when no toggle is active; leading-separator-then-name fragment per active toggle. Authors can override via a function `toggle_<name>_statusline`.
- Library helpers: `lib/scope.sh`, `lib/command_call.sh`, `lib/hook_io.sh` (`block_userprompt`, `inject_context`, `deny_pretooluse`, `deny_with_errors`, `hook_log`), `lib/toggle.sh`.
- `TOGGLE_API` schema version, `TOGGLE_EXTRA_HOOKS` for peer enforcement scripts, `TOGGLE_ANNOUNCE_ON_TOGGLE`, `TOGGLE_ANNOUNCE_ON_SESSION_START`, `TOGGLE_REANNOUNCE_EVERY`, `TOGGLE_STATUSLINE`, `TOGGLE_MARKER`.
- Reference toggles under `examples/`: `coauth` (project-scope; ships a peer `commit-check.sh`) and `devlog` (session-scope; silent flips; custom statusline fragment).
- Per-toggle `permissions.deny` rules templated into `settings.json` to prevent direct sentinel writes from the model.
- Settings.json merge invariants: `jq --indent 2`, append-not-union for `permissions.deny`, sentinel-comment tagging for round-trip identification, `flock` against concurrent writes.
- Test suite: 96 bats cases covering scope, toggle primitives, command detection, hook I/O, dispatcher, statusline, install, uninstall, end-to-end, examples.
- Tooling: `Makefile` (`make lint fmt fmt-check test check hooks clean`), `.shellcheckrc`, `.editorconfig`, pre-commit and pre-push hook installer (`scripts/install-git-hooks.sh`), GitHub Actions CI.
- Documentation: `README.md`, `CONTRIBUTING.md`, PR template, bug and feature issue templates.
- Repo: branch protection on `main` (PR-only, squash merge, required `lint` and `test` checks, no bypass).

### Notes

- The CLI is bash for v0.1.0. A native binary rewrite (Go) is planned for v0.2.0; the CLI surface is final.
