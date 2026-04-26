# claudetoggle

[![ci](https://github.com/spuddydev/claudetoggle/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/spuddydev/claudetoggle/actions/workflows/ci.yml)
[![licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

Add `/yourtoggle` slash commands to Claude Code with one file. Each toggle flips a rule on or off — for the project, the session, or globally — and tells the model the new state.

> Want to hack on the framework itself? See [CONTRIBUTING.md](CONTRIBUTING.md). Release log: [CHANGELOG.md](CHANGELOG.md).

## Why you'd use this

A toggle is a one-liner for a behaviour you want to switch on and off mid-conversation. Real examples:

- **`/coauth`** — flip the `Co-Authored-By: Claude` trailer policy for this repo. Type `/coauth` once, every commit Claude writes from now on includes the trailer (or doesn't).
- **`/devlog`** — keep a running journal of decisions in `.claude/devlog/` for this session.
- **`/precommit`** — turn pre-commit hooks off for an emergency hotfix without touching `--no-verify` everywhere.
- **`/safetynet`** — refuse `git push --force`, `rm -rf` and friends until you flip it back off.

Without a framework, each of these means writing a hook script, editing `settings.json`, adding a slash-command markdown, telling the model the rule changed, plus reannouncing it every few prompts so it doesn't forget. claudetoggle does all of that from one short metadata file per toggle.

## Quick start

**1. Install:**

```sh
git clone https://github.com/spuddydev/claudetoggle ~/projects/claudetoggle
cd ~/projects/claudetoggle
./install.sh
```

**2. Author a toggle.** Drop a directory under `~/.claude/toggles/`:

```sh
mkdir -p ~/.claude/toggles/safetynet
cat >~/.claude/toggles/safetynet/toggle.sh <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=safetynet
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="safetynet is ON: refuse git push --force, rm -rf, and any irreversible filesystem operation. Ask the user to flip it off if they really want it."
TOGGLE_OFF_MSG="safetynet is OFF."
TOGGLE_MARKER="<!-- safetynet-marker -->"
EOF

cat >~/.claude/toggles/safetynet/safetynet.md <<'EOF'
---
description: Toggle the safety net for this session. User-invokable only.
---
<!-- safetynet-marker -->
The user just typed `/safetynet`. The dispatcher already flipped state and announced. Acknowledge in one short line.
EOF
```

**3. Run install again** to wire it up:

```sh
./install.sh
```

**4. In Claude Code, type `/safetynet`.** The toggle flips on, the model sees the new rule, the statusline shows `safetynet`. Type it again to flip off.

That's the whole loop. Two files plus a re-run of `install.sh`.

## How a toggle works

Every toggle lives at `~/.claude/toggles/<name>/` with at minimum:

- `toggle.sh` — six lines of metadata (name, scope, the on and off messages).
- `<name>.md` — the slash-command body Claude Code parses; tiny.

When the user types `/<name>`:

1. A single shared dispatcher (set up by `install.sh`) intercepts the prompt.
2. It flips a tiny sentinel file under `~/.claude/toggles/.state/<name>/`.
3. It blocks the prompt and tells the model the new state — that's how the rule "lands" without needing the model to read disk.
4. The next time the model talks, it knows the rule is on (or off).

You don't write the dispatcher. You don't edit `settings.json`. You write the metadata file and an install rerun does the rest.

## The metadata file in detail

Every toggle declares these:

| Variable | Required | Default | What it does |
|---|---|---|---|
| `TOGGLE_API` | yes | — | Schema version. Set to `1`. |
| `TOGGLE_NAME` | yes | — | Short name. Must match the directory name. |
| `TOGGLE_SCOPE` | yes | — | `global`, `project`, or `session`. |
| `TOGGLE_ON_MSG` | yes | — | Text injected to the model when flipped on or reannounced. |
| `TOGGLE_OFF_MSG` | yes | — | Text shown when flipped off. |
| `TOGGLE_MARKER` | optional | none | Substring in the slash-command markdown body for forward-compatible detection. Recommended. |
| `TOGGLE_REANNOUNCE_EVERY` | optional | `0` | Reinject `ON_MSG` every N prompts. `0` = announce once on flip, never again. |
| `TOGGLE_ANNOUNCE_ON_SESSION_START` | optional | `1` | Print `ON_MSG` at session start when the toggle is on. |
| `TOGGLE_ANNOUNCE_ON_TOGGLE` | optional | `1` | Block the prompt and announce on flip. Set to `0` for silent toggles whose effect is purely behind-the-scenes. |
| `TOGGLE_STATUSLINE` | optional | `1` | Show this toggle on the statusline when on. |
| `TOGGLE_EXTRA_HOOKS` | optional | empty | One entry per extra event hook (see below). |

A toggle may also define a function `toggle_<name>_statusline` to override the default statusline fragment. The function is called per redraw inside a subshell, so it must be fast and side-effect-free.

## Adding extra enforcement scripts

Sometimes a toggle isn't just "tell the model the rule" — you want to **enforce** it with a hook. Example: `/precommit` should make `git commit` fail when on.

Drop a peer script in the toggle's directory and register it via `TOGGLE_EXTRA_HOOKS`:

```sh
# ~/.claude/toggles/precommit/toggle.sh
TOGGLE_API=1
TOGGLE_NAME=precommit
TOGGLE_SCOPE=project
TOGGLE_ON_MSG="precommit is ON: pre-commit hooks must run."
TOGGLE_OFF_MSG="precommit is OFF: skipping pre-commit hooks for this turn."
TOGGLE_MARKER="<!-- precommit-marker -->"

# When precommit is OFF, run a peer script before every git commit to
# strip --no-verify (or whatever your gate is).
TOGGLE_EXTRA_HOOKS=()
TOGGLE_EXTRA_HOOKS+=("PreToolUse"$'\x1f'"Bash"$'\x1f'"Bash(git commit *)"$'\x1f'"check.sh")
```

The four pipe-separated fields are: **event** (e.g. `PreToolUse`), **matcher** (e.g. `Bash`), **if-clause** (Claude Code's filter syntax, e.g. `Bash(git commit *)`), **script** (relative to the toggle's directory). The separator `$'\x1f'` is the ASCII unit-separator — chosen because it never appears inside an `if`-clause.

Your peer script reads the hook's stdin JSON and decides what to do. Source the framework helpers like this:

```sh
#!/usr/bin/env bash
CLAUDETOGGLE_LIB=${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "$0")")/../.lib}
. "$CLAUDETOGGLE_LIB/hook_io.sh"
. "$CLAUDETOGGLE_LIB/scope.sh"

# Read input, decide, then either exit 0 (allow) or:
#   deny_pretooluse "your reason here"
```

After editing `TOGGLE_EXTRA_HOOKS` or adding a peer script, **rerun `./install.sh`** to wire it into `settings.json`.

See [`examples/coauth/`](examples/coauth/) for a complete worked example.

## Statusline integration

Add this to the script your statusline already runs (the one referenced by `statusLine.command` in `settings.json`):

```sh
. "$HOME/.claude/toggles/.bin/statusline.sh"
export CLAUDE_CWD="$cwd" CLAUDE_SESSION_ID="$session"
left+="$(claudetoggle_statusline)"
```

`$cwd` and `$session` come from your statusline's existing JSON parse. The function emits a leading separator only when output is non-empty, so you append unconditionally and get nothing when no toggles are on.

`install.sh` prints this snippet for you if it detects you haven't wired it in yet. It does **not** mutate your existing statusline script — that's yours.

## Install / uninstall / upgrade

```sh
./install.sh                    # one-time setup, then re-run after editing toggles
./uninstall.sh                  # remove framework wiring; preserves state under .state/
./uninstall.sh --purge          # also delete state and ~/.claude/toggles/
```

**To upgrade:** `cd ~/projects/claudetoggle && git pull && ./install.sh`. The install copies the framework's `lib/` and `bin/` into `~/.claude/toggles/.lib` and `~/.claude/toggles/.bin`; rerunning re-copies. Standard pattern, like any CLI tool.

Override paths with `CLAUDE_HOME=...`, `CLAUDETOGGLE_HOME=...`, or `--prefix=DIR`.

## Troubleshooting

Set `CLAUDETOGGLE_DEBUG=1` in your shell. The dispatcher and helpers append timestamped lines to `~/.claude/toggles/.debug.log`. Tail it while you reproduce the issue.

You can drive the dispatcher directly to inspect its behaviour:

```sh
printf '{"hook_event_name":"UserPromptSubmit","prompt":"/coauth","cwd":"'"$PWD"'","session_id":"x"}' \
  | bash ~/.claude/toggles/.bin/dispatch.sh UserPromptSubmit
```

## Known limits

- The statusline forks one subshell per registered toggle on every redraw. Fine at five toggles, sluggish at twenty. A cache will land if anyone reports it.

## Licence

MIT. See [LICENSE](LICENSE).
