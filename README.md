# claudetoggle

[![ci](https://github.com/spuddydev/claudetoggle/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/spuddydev/claudetoggle/actions/workflows/ci.yml)
[![licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

Add `/yourtoggle` slash commands to Claude Code with one file. Each toggle flips a rule on or off — for the project, the session, or globally — and tells the model the new state.

> Writing your own toggle? See [docs/AUTHORING.md](docs/AUTHORING.md). Hacking on the framework? See [CONTRIBUTING.md](CONTRIBUTING.md). Release log: [CHANGELOG.md](CHANGELOG.md).

## Why you'd use this

A toggle is a one-liner for a behaviour you want to switch on and off mid-conversation. Real examples:

- **`/coauth`** — flip the `Co-Authored-By: Claude` trailer policy for this repo.
- **`/devlog`** — keep a running journal in `.claude/devlog/` for this session.
- **`/precommit`** — turn pre-commit hooks off for an emergency hotfix without sprinkling `--no-verify`.
- **`/safetynet`** — refuse `git push --force`, `rm -rf` and friends until you flip it back off.

Without a framework, each of these means writing a hook script, editing `settings.json`, adding a slash-command markdown, telling the model the rule changed, plus reannouncing it every few prompts. claudetoggle does all of that from one short metadata file per toggle.

## Install

```sh
curl -sSfL https://raw.githubusercontent.com/spuddydev/claudetoggle/main/setup.sh | sh
```

That fetches the latest release, places framework files under `$XDG_DATA_HOME/claudetoggle/` (defaulting to `~/.local/share/claudetoggle/`), installs the `claudetoggle` CLI to `~/.local/bin/`, and wires the dispatcher into `~/.claude/settings.json`.

If `~/.local/bin` isn't on your `$PATH`, the installer prints the exact line to add to your shell config.

Tagged releases ship with a `SHA256SUMS` asset and the installer verifies the tarball against it before unpacking. Set `CLAUDETOGGLE_SKIP_VERIFY=1` (or pass `--skip-verify`) only if you really need to bypass the check.

**From a clone, for development or audit-first install:**

```sh
git clone https://github.com/spuddydev/claudetoggle
cd claudetoggle
./setup.sh --local
```

## Add a toggle in 60 seconds

Pick a shipped example:

```sh
claudetoggle add coauth
claudetoggle list
```

Or roll your own. Drop a directory anywhere, then `claudetoggle add` it:

```sh
mkdir -p ~/projects/safetynet
cat >~/projects/safetynet/toggle.sh <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=safetynet
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="safetynet is ON: refuse git push --force, rm -rf and any irreversible filesystem operation. Ask the user to flip it off if they really want it."
TOGGLE_OFF_MSG="safetynet is OFF."
TOGGLE_MARKER="<!-- safetynet-marker -->"
EOF

cat >~/projects/safetynet/safetynet.md <<'EOF'
---
description: Toggle the safety net for this session. User-invokable only.
---
<!-- safetynet-marker -->
The user just typed `/safetynet`. The dispatcher already flipped state and announced. Acknowledge in one short line.
EOF

claudetoggle add ~/projects/safetynet
```

Now in Claude Code, type `/safetynet`. The toggle flips on, the model sees the new rule, the statusline shows `safetynet`. Type it again to flip off.

## CLI reference

```
claudetoggle add <name|path>      register a shipped example or a local directory
                                  (--dry-run to preview without writing)
claudetoggle remove <name>        unregister and delete a toggle (--keep-state to preserve,
                                  --dry-run to preview)
claudetoggle list                 show registered toggles and current state
claudetoggle on <name>            flip a toggle ON in the current scope
claudetoggle off <name>           flip a toggle OFF in the current scope
claudetoggle update               re-run setup.sh against the latest release
claudetoggle uninstall            unwire claudetoggle (--purge to also delete data and CLI)
claudetoggle doctor               diagnostic dump
claudetoggle version              print the installed version
claudetoggle help                 full reference
```

Tip: `claudetoggle on <name>` and `claudetoggle off <name>` work outside Claude Code too — handy for scripting or flipping a toggle from your shell without touching the chat.

## How a toggle works

Every toggle lives at `$XDG_DATA_HOME/claudetoggle/toggles/<name>/` with at minimum:

- `toggle.sh` — six lines of metadata (name, scope, the on and off messages).
- `<name>.md` — the slash-command body Claude Code parses; tiny.

When the user types `/<name>`:

1. A single shared dispatcher (set up by `setup.sh`) intercepts the prompt.
2. It flips a sentinel file under `<data>/state/<name>/`.
3. It blocks the prompt and tells the model the new state — that's how the rule "lands" without needing the model to read disk.
4. The next time the model talks, it knows the rule is on (or off).

You don't write the dispatcher. You don't edit `settings.json`. You write the metadata file (and optionally peer enforcement scripts) and `claudetoggle add` does the rest.

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

Sometimes a toggle needs to **enforce** a rule, not just tell the model. Example: `/precommit` should make `git commit` fail when off.

Drop a peer script alongside `toggle.sh` and register it via `TOGGLE_EXTRA_HOOKS`:

```sh
# ~/projects/precommit/toggle.sh
TOGGLE_API=1
TOGGLE_NAME=precommit
TOGGLE_SCOPE=project
TOGGLE_ON_MSG="precommit is ON: pre-commit hooks must run."
TOGGLE_OFF_MSG="precommit is OFF: skipping pre-commit hooks for this turn."
TOGGLE_MARKER="<!-- precommit-marker -->"

TOGGLE_EXTRA_HOOKS=()
TOGGLE_EXTRA_HOOKS+=("PreToolUse"$'\x1f'"Bash"$'\x1f'"Bash(git commit *)"$'\x1f'"check.sh")
```

Then `claudetoggle add ~/projects/precommit`. The four pipe-separated fields are: **event** (`PreToolUse`), **matcher** (`Bash`), **if-clause** (`Bash(git commit *)`), **script path** (relative to the toggle's directory). The separator `$'\x1f'` is the ASCII unit-separator, chosen because it never appears inside an if-clause.

Your peer script reads the hook's stdin JSON and decides what to do. Source the framework helpers like this:

```sh
#!/usr/bin/env bash
CLAUDETOGGLE_LIB=${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "$0")")/../../lib}
. "$CLAUDETOGGLE_LIB/hook_io.sh"
. "$CLAUDETOGGLE_LIB/scope.sh"

# Read input, decide, then either exit 0 (allow) or:
#   deny_pretooluse "your reason here"
```

Two `..` because peer scripts live at `<data>/toggles/<name>/<peer>.sh`, two levels below the framework lib at `<data>/lib/`.

After editing a registered toggle's metadata, run `claudetoggle remove <name>` then `claudetoggle add <path>` to re-register with the changes.

See [`examples/coauth/`](examples/coauth/) for a complete worked example. The full schema reference, scope semantics, idempotency rules and peer-script patterns live in [docs/AUTHORING.md](docs/AUTHORING.md).

### Scaffolding skill

If you want Claude to draft a new toggle for you, ask it: *"create a toggle that ..."*. The installer ships a `create-claudetoggle` skill into `~/.claude/skills/` that walks the model through the schema, generates the files into a directory of your choice, and prints the exact `claudetoggle add` command for you to run. It will not register the toggle for you — review it first.

## Statusline integration

Add this to the script your statusline already runs (the one referenced by `statusLine.command` in `settings.json`):

```sh
. "$HOME/.local/share/claudetoggle/bin/statusline.sh"
export CLAUDE_CWD="$cwd" CLAUDE_SESSION_ID="$session"
left+="$(claudetoggle_statusline)"
```

`$cwd` and `$session` come from your statusline's existing JSON parse. The function emits a leading separator only when output is non-empty, so you append unconditionally and get nothing when no toggles are on.

`setup.sh` prints this snippet for you. It does not mutate your existing statusline script — that's yours.

## Upgrade

```sh
claudetoggle update
```

Re-runs `setup.sh` against the latest release, replaces framework files, and re-wires the dispatcher idempotently. Your registered toggles and state are untouched.

## Uninstall

```sh
claudetoggle uninstall              # unwire from settings.json; preserves data, state, CLI
claudetoggle uninstall --purge      # also remove $XDG_DATA_HOME/claudetoggle and the CLI
```

## Troubleshooting

Set `CLAUDETOGGLE_DEBUG=1` in your shell. The dispatcher and helpers append timestamped lines to `~/.local/share/claudetoggle/debug.log`. Tail it while you reproduce the issue.

You can drive the dispatcher directly to inspect its behaviour:

```sh
printf '{"hook_event_name":"UserPromptSubmit","prompt":"/coauth","cwd":"'"$PWD"'","session_id":"x"}' \
  | bash ~/.local/share/claudetoggle/bin/dispatch.sh UserPromptSubmit
```

`claudetoggle doctor` prints resolved paths, settings.json sanity, the registry, and the last few debug lines — start there for any "is this set up right?" question.

## Known limits

- The statusline forks one subshell per registered toggle on every redraw. Fine at five toggles, sluggish at twenty. A cache will land if anyone reports it.
- The CLI is bash for v0.1.0. A native binary rewrite (Go) is on the roadmap; the CLI surface won't change.

## Licence

MIT. See [LICENSE](LICENSE).
