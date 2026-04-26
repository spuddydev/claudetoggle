# Contributing

Thanks for considering a patch. This page is for hacking on the framework. If you only want to author your own toggle, see [README.md](README.md) instead.

## Workflow

- Branch per change. Open a pull request when ready.
- `main` is protected: PR-only, squash merge, required CI checks `lint` and `test`, no bypass for anyone.
- Re-merge by squash. The squashed commit lands on `main`; feature branches are deleted on merge.

If GitHub blocks your merge with "branch is behind", use the **Update branch** button (or `gh pr update-branch`) and let CI re-run; do not force-push.

## One-time setup

```sh
git clone https://github.com/spuddydev/claudetoggle
cd claudetoggle
make hooks
```

`make hooks` installs local pre-commit (lint + format check on staged shell files) and pre-push (full bats suite) hooks.

## Install bats

The pre-push hook silently skips when `bats` is missing — CI catches the gap regardless, but local feedback is faster:

- Debian / Ubuntu: `sudo apt install bats`
- macOS: `brew install bats-core`
- From source: `git clone https://github.com/bats-core/bats-core` and run via `bats-core/bin/bats`

## Before pushing

```sh
make check    # lint, fmt-check, test
```

If you only touched specific files, `shellcheck path/to/file.sh` and `shfmt -d path/to/file.sh` are quick spot-checks.

## What lives where

```
lib/                  framework helpers (scope, toggle, command_call, hook_io)
bin/                  dispatcher and statusline (one each)
scripts/              repo-only helpers (settings_merge.sh, git-hooks)
examples/             reference toggles (NOT auto-installed)
tests/                bats test suite
install.sh
uninstall.sh
```

User toggles live at `~/.claude/toggles/<name>/`. Framework internals get copied at install time into `~/.claude/toggles/.lib` and `~/.claude/toggles/.bin`. State (sentinels, counters, debug log) lives under `~/.claude/toggles/.state/` and `~/.claude/toggles/.debug.log`.

## Adding a new example toggle

1. Create `examples/<name>/` with `toggle.sh`, `<name>.md`, and any peer scripts.
2. Add `<name>` to `examples/README.md`.
3. Add bats coverage in `tests/examples.bats` mirroring the existing assertions: `bash -n` parses, sourcing yields all required vars, `TOGGLE_NAME` matches the dirname, and `<name>.md` carries the marker comment.
4. Run `make check`.

## Adding a new `TOGGLE_*` variable

1. Document it in the registry-file header comment in `lib/toggle.sh` (the canonical reference for the schema).
2. Extend `toggle_reset` to unset it.
3. Wire it through `bin/dispatch.sh` and/or `bin/statusline.sh`.
4. Update the variable reference table in `README.md`.
5. Add at least one bats case asserting the new behaviour.

## Adding a new framework helper

Helpers are tiny on purpose. Keep them in the right lib file:

- `scope.sh` — path computation
- `toggle.sh` — registry, state, counter
- `command_call.sh` — slash-command detection
- `hook_io.sh` — JSON output and the debug log

Each new helper gets bats coverage in the matching `tests/<name>.bats` file.

## Debugging

- `CLAUDETOGGLE_DEBUG=1` in your shell makes the dispatcher and helpers log to `~/.claude/toggles/.debug.log`.
- The dispatcher reads its event from argv first, JSON `.hook_event_name` second. Drive it directly: `printf '<json>' | bash bin/dispatch.sh UserPromptSubmit`.
- Statusline output is whatever `claudetoggle_statusline` prints. Source the snippet directly to inspect.

## Style

House style is **British English** for prose and code-emitted strings (organise, behaviour, colour). Outside contributors writing US English are welcome; copy may be normalised on merge.

### Commits

- Plain words, no symbols. `+` becomes "and"; em dashes are minimised.
- No code-speak — no function names, file names, flag names. Reviewers read the diff for "what".
- Prefer short bullets to long sentences.
- Header `<= 50` characters.

### Pull requests

- Concise. Short summary, short bullets, no padding. Use the PR template.
- Code-speak is fine in PRs when unavoidable for clarity.
- A test-plan checklist is welcome.

## Releases

Releases are tagged `vX.Y.Z` and recorded in `CHANGELOG.md`. The project is pre-1.0, so MINOR bumps may include breaking changes; the changelog calls them out explicitly.
