# claudetoggle

Tiny Bash framework for adding toggleable Claude Code hooks. One declaration file per toggle, one generic dispatcher, one statusline indicator. Drop a directory in, run install, get a `/yourtoggle` slash command that flips a per-project, per-session, or global rule and announces the new state to the model.

This README is for toggle authors. See [CONTRIBUTING.md](CONTRIBUTING.md) if you want to hack on the framework itself.

## 60-second walkthrough

Author a minimum-viable toggle:

```sh
mkdir -p ~/.claude/toggles/foo
cat >~/.claude/toggles/foo/toggle.sh <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=foo
TOGGLE_SCOPE=project
TOGGLE_ON_MSG="foo is ON for this project — be very careful with file deletes."
TOGGLE_OFF_MSG="foo is OFF for this project."
TOGGLE_MARKER="<!-- foo-marker -->"
EOF

cat >~/.claude/toggles/foo/foo.md <<'EOF'
---
description: Toggle the foo policy for this project. User-invokable only.
---
<!-- foo-marker -->
The user just typed `/foo`. The dispatcher already flipped state and announced. Acknowledge in one short line.
EOF

./install.sh
```

Now in any Claude Code session: type `/foo` and the dispatcher flips the per-project sentinel, blocks the prompt, and tells the model the new state. Type `/foo` again to flip back. The statusline shows `foo` while ON.

## Architecture

- **Registry** — every toggle is a directory at `~/.claude/toggles/<name>/`, holding a metadata file `toggle.sh`, a slash-command markdown `<name>.md`, and any peer scripts the toggle declares via `TOGGLE_EXTRA_HOOKS`.
- **Dispatcher** — one shared dispatcher (installed at `~/.claude/toggles/.bin/dispatch.sh`) is wired to `UserPromptSubmit` and `SessionStart`, iterates the registry, and handles every toggle's flip/announce/reannounce contract.
- **Statusline** — one shared statusline snippet (installed at `~/.claude/toggles/.bin/statusline.sh`) defines `claudetoggle_statusline`, returning a leading-separator-then-name fragment per active toggle. Empty when nothing is active.
- **Install** — `install.sh` copies the framework into `~/.claude/toggles/.lib` and `~/.claude/toggles/.bin`, merges the dispatcher and per-toggle deny rules into `~/.claude/settings.json`, and symlinks slash-command markdowns into `~/.claude/commands/`.

## `TOGGLE_*` reference

| Variable | Default | Description |
|---|---|---|
| `TOGGLE_API` | (required) | Schema version. Only `1` is accepted. Unset rejected. |
| `TOGGLE_NAME` | (required) | Short name. Must match the directory name. |
| `TOGGLE_SCOPE` | (required) | One of `global`, `project`, `session`. |
| `TOGGLE_ON_MSG` | (required) | Text shown to the model when the toggle is flipped ON or reannounced. |
| `TOGGLE_OFF_MSG` | (required) | Text shown when flipped OFF. |
| `TOGGLE_MARKER` | (none) | Optional substring in the slash-command markdown body for forward-compatible detection. |
| `TOGGLE_REANNOUNCE_EVERY` | `0` | Reinject `ON_MSG` after this many ordinary prompts. `0` means announce once on flip and never again. |
| `TOGGLE_ANNOUNCE_ON_SESSION_START` | `1` | Print `ON_MSG` at session start when the toggle is active. |
| `TOGGLE_ANNOUNCE_ON_TOGGLE` | `1` | Block the prompt and announce on flip. Set to `0` for silent toggles whose effect is purely behind-the-scenes. |
| `TOGGLE_STATUSLINE` | `1` | Show this toggle on the statusline when active. |
| `TOGGLE_EXTRA_HOOKS` | empty array | One entry per extra event hook. See below. |

A registry file may also define a function `toggle_<name>_statusline` to override the default statusline fragment. The function is called in a subshell on every redraw, so it must be fast and side-effect-free.

## `TOGGLE_EXTRA_HOOKS`

For toggles that need to register additional hook entries (typically `PreToolUse(Bash)` enforcement scripts), declare them as an array of pipe-separated entries. The separator is the ASCII unit-separator `\x1f`, which avoids quoting collisions with anything that might appear in `if` clauses.

```sh
TOGGLE_EXTRA_HOOKS=()
TOGGLE_EXTRA_HOOKS+=("Event"$'\x1f'"Matcher"$'\x1f'"if-clause"$'\x1f'"script.sh")
```

Concrete example from `examples/coauth/toggle.sh`:

```sh
TOGGLE_EXTRA_HOOKS+=("PreToolUse"$'\x1f'"Bash"$'\x1f'"Bash(git commit *)"$'\x1f'"commit-check.sh")
```

`script.sh` lives alongside `toggle.sh` in the toggle's directory. Peer scripts source the framework lib via:

```sh
CLAUDETOGGLE_LIB=${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "$0")")/../.lib}
. "$CLAUDETOGGLE_LIB/hook_io.sh"
```

One `..` because peer scripts live at `~/.claude/toggles/<name>/peer.sh`, one level below the framework lib at `~/.claude/toggles/.lib/`.

## Statusline integration

Add this to your existing statusline script (paste-ready):

```sh
. "$HOME/.claude/toggles/.bin/statusline.sh"
export CLAUDE_CWD="$cwd" CLAUDE_SESSION_ID="$session"
left+="$(claudetoggle_statusline)"
```

Where `$cwd` and `$session` come from your statusline's existing JSON parse. The function emits a leading separator when output is non-empty so you can append unconditionally; empty stdout when nothing is active. Override the separator with `CLAUDETOGGLE_STATUSLINE_SEP=` if needed; the default is ` │ `.

`install.sh` does not mutate your `statusLine.command`. It detects whether your statusline already sources the snippet; if not, it prints the integration block to stdout.

## Install / uninstall / upgrade

```sh
git clone https://github.com/<you>/claudetoggle ~/projects/claudetoggle
cd ~/projects/claudetoggle
./install.sh
```

Override paths with `CLAUDE_HOME=`, `CLAUDETOGGLE_HOME=`, or `--prefix=DIR`.

`./uninstall.sh` removes everything claudetoggle installed but preserves state. `./uninstall.sh --purge` also deletes `~/.claude/toggles/`.

**Upgrade:** `cd <repo> && git pull && ./install.sh`. The install copies the framework's `lib/` and `bin/` into `~/.claude/toggles/.lib` and `~/.claude/toggles/.bin`; rerunning `install.sh` re-copies. Adding a toggle, editing one's metadata, or adding a `TOGGLE_EXTRA_HOOKS` entry also requires a rerun.

## Known limits

- The statusline forks one subshell per registered toggle on every redraw. Fine at five toggles, sluggish at twenty. A cache will land if anyone reports it.

## Troubleshooting

Set `CLAUDETOGGLE_DEBUG=1` in your shell before running Claude Code; the dispatcher and helpers append timestamped entries to `~/.claude/toggles/.debug.log`.

## Licence

MIT. See [LICENSE](LICENSE).
