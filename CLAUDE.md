# Working in this repo

Claudetoggle is a tiny framework for adding user-flippable toggles to Claude Code. A toggle is a directory with a metadata file and a slash-command body; the framework wires the rest. CONTRIBUTING.md covers the workflow and house style; this file is the orientation a fresh session needs to be useful here.

## Layout at a glance

```
bin/        claudetoggle CLI; dispatch.sh; statusline.sh
lib/        scope.sh, toggle.sh, command_call.sh, hook_io.sh
scripts/    settings_merge.sh and git hook helpers
examples/   reference toggles (NOT auto-installed; user opts in via add)
toggles/    empty in-repo; populated at $CLAUDETOGGLE_HOME/toggles/<name>/ on install
tests/      bats suite, one file per lib + dispatch + e2e
setup.sh    single install entry point; idempotent re-run for upgrades
```

User-facing data home is `$XDG_DATA_HOME/claudetoggle` (default `~/.local/share/claudetoggle`); not `~/.claude/`. State sentinels live under `state/<name>/`.

## Invariants you must preserve

- **One shared dispatcher hook.** `setup.sh` registers exactly one entry under `hooks.UserPromptSubmit[0].hooks` and one under `hooks.SessionStart[0].hooks`, both pointing at `bin/dispatch.sh`. The dispatcher iterates the registry. Per-toggle hooks are reserved for `TOGGLE_EXTRA_HOOKS`.
- **Settings entries are tagged.** Every command claudetoggle writes into `~/.claude/settings.json` carries a `# claudetoggle:...` shell-comment sentinel. `settings_remove_tagged` matches on that substring. Don't write untagged entries.
- **Slash flips inject context, not block.** `dispatch.sh handle_user_prompt_match` calls `inject_context "$msg"`. Returning `{decision:"block",reason:...}` only surfaces text in the UI — the model never sees it. The only path that legitimately uses `block_userprompt` is the scope-error case (no valid cwd / session id), where stopping the prompt is the right call.
- **CLI flips queue a pending message.** `cmd_on` / `cmd_off` write `TOGGLE_ON_MSG` / `TOGGLE_OFF_MSG` to `state/<name>/pending`. `handle_reannounce` drains it on the next `UserPromptSubmit`. A subsequent slash flip in the same prompt clears the pending file via `toggle_pending_clear` so messages don't double-inject.
- **Reannounce counter is single-shared, not per-session.** One counter at `state/<name>/counter`, locked via `flock` (or mkdir fallback for macOS). Slash flip-to-ON resets it to `0` because the flip itself already injected `ON_MSG` for this turn.
- **Sentinel paths are deterministic.** `lib/scope.sh` is the single source of truth: `global` → `state/<name>/global`; `project` → `state/<name>/projects/<sha256-prefix-of-git-root-or-cwd>`; `session` → `state/<name>/sessions/<id>`. Don't compute these by hand elsewhere.
- **Permissions deny rules guard the state dir.** `deny_globs_for_toggle` emits `Bash(<verb> *claudetoggle/state/<name>/*)` patterns so the model can't `touch` a sentinel into existence. Any new write verb (touch, rm, rmdir, mv, cp, chmod, ln, tee, redirections) needs a deny rule there.
- **Shellcheck and shfmt are mandatory.** `make check` runs lint + fmt-check + bats. Pre-commit and pre-push hooks installed via `make hooks` enforce locally.
- **British English in prose and emitted strings** (organise, behaviour, colour).

## Local development loop

```sh
# Install into a sandboxed home so you don't touch your real ~/.claude.
tmp=$(mktemp -d)
export CLAUDE_HOME="$tmp/.claude" \
       CLAUDETOGGLE_HOME="$tmp/.local/share/claudetoggle" \
       PREFIX="$tmp/.local"
bash setup.sh --local
"$PREFIX/bin/claudetoggle" add coauth
```

Drive the dispatcher directly to inspect output without booting Claude Code:

```sh
printf '{"prompt":"/coauth","cwd":"%s","session_id":"%s"}' "$PWD" sid \
  | bash "$CLAUDETOGGLE_HOME/bin/dispatch.sh" UserPromptSubmit
```

`CLAUDETOGGLE_DEBUG=1` writes timestamped lines to `$CLAUDETOGGLE_HOME/debug.log`.

Run a single test file: `bats tests/dispatch.bats`. The full suite: `make test`.

## Common tasks

- **Add a `TOGGLE_*` variable**: document it in the `lib/toggle.sh` header comment, add it to `toggle_reset`, wire through `bin/dispatch.sh` and/or `bin/statusline.sh`, update the README table, add a bats case. CONTRIBUTING.md spells this out.
- **Add an example toggle**: `examples/<name>/{toggle.sh,<name>.md,...}`, list it in `examples/README.md`, add coverage in `tests/examples.bats`. Examples are not auto-installed.
- **Change settings.json schema**: edit `scripts/settings_merge.sh` and the matching `tests/install.bats` cases. Keep writes idempotent (sentinel-tagged + dedup-on-rule-string).
- **Statusline integration**: prefer `claudetoggle statusline` (reads JSON from stdin or `--cwd`/`--session`) over the sourceable form. The sourceable `bin/statusline.sh` still works for bash-host statuslines.

## Things that are NOT bugs

- `claudetoggle add foo` does not install the central dispatcher hook — `setup.sh` does, once. `add` only wires per-toggle pieces (deny rules, `TOGGLE_EXTRA_HOOKS`, slash-command symlink). If a user reports "add silently did nothing", check that they ran `setup.sh` first.
- Project-scope toggles silently no-op when there's no cwd and session-scope toggles silently no-op when there's no session id. The dispatcher returns scope code `2` and skips quietly. Only an explicit slash-command invocation surfaces the scope error to the user.
- Re-running `setup.sh` is the supported upgrade path. It re-copies framework files, re-applies the dispatch entries, and leaves user toggles and state untouched.
