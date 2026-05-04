# Authoring a toggle

This is the reference for people writing their own toggle. If you only want to use a shipped one, see [README.md](../README.md).

> **Shortcut**: if claudetoggle is installed, the `create-claudetoggle` skill (at `~/.claude/skills/create-claudetoggle/`) walks Claude through this document and scaffolds a new toggle for you. Just ask: *"create a toggle that ..."*. Use this guide when you want the full picture or are writing one by hand.

A toggle is two files plus optional peer scripts. The framework does the dispatcher, the slash-command wiring, the deny rules and the statusline indicator. You provide:

- `toggle.sh` — metadata (the name, the scope, the messages).
- `<name>.md` — the slash-command body Claude Code parses.
- (optional) `*.sh` peer scripts that enforce the toggle's rule via hooks.

That is the whole interface.

## Layout on disk

```
<your-toggle-dir>/
  toggle.sh           # required — metadata
  <name>.md           # required if you want a /<name> slash command
  <peer>.sh           # optional — one per TOGGLE_EXTRA_HOOKS entry
```

After `claudetoggle add <dir>`, the directory is copied to `$CLAUDETOGGLE_HOME/toggles/<name>/`. State lives separately under `$CLAUDETOGGLE_HOME/state/<name>/`.

## Naming rules

- `<name>` must be lowercase, with letters, digits and dashes only. No underscores in the slash command (Claude Code restriction); use dashes.
- The directory name, `TOGGLE_NAME`, and the markdown filename must all match exactly.
- Pick something short and verb-like: `coauth`, `devlog`, `safetynet`, `precommit`. The user types it as `/<name>`.

## `toggle.sh` — every variable

```sh
# Required schema version. Only "1" is accepted today; anything else is rejected.
TOGGLE_API=1

# Required short name. Must equal the directory name.
TOGGLE_NAME=coauth

# Required scope. One of:
#   global   — one sentinel for the whole machine
#   project  — keyed by sha256 of the git root (or cwd if not a repo)
#   session  — keyed by Claude Code session id
TOGGLE_SCOPE=project

# Required text injected to the model when the toggle is flipped ON, or
# reannounced. Write it as a complete instruction the model can follow on its
# own — it lands as a system reminder, not a chat message.
TOGGLE_ON_MSG="coauth is ON for this project: include a Co-Authored-By: Claude trailer on every commit."

# Required text shown when flipped OFF. Same shape as ON_MSG but describes
# the absence of the rule.
TOGGLE_OFF_MSG="coauth is OFF: do not add a Co-Authored-By trailer."

# Optional. A unique substring placed inside <name>.md so the dispatcher can
# detect the slash-command invocation even if Claude Code expands the
# markdown body into the prompt verbatim. Recommended for every toggle.
TOGGLE_MARKER="<!-- coauth-toggle-marker -->"

# Optional. Re-inject ON_MSG every N ordinary prompts while the toggle is ON.
# 0 (default) = announce once on flip, never again. The counter is global
# across sessions, persists on disk, and resets to 0 whenever the toggle
# flips OFF.
TOGGLE_REANNOUNCE_EVERY=10

# Optional. 1 (default) = print ON_MSG at SessionStart when ON. 0 = silent.
TOGGLE_ANNOUNCE_ON_SESSION_START=1

# Optional. 1 (default) = inject the on/off message into the model's context
# on flip so the rule lands the same turn. 0 = flip silently (for toggles
# whose effect is purely behind-the-scenes via TOGGLE_EXTRA_HOOKS).
TOGGLE_ANNOUNCE_ON_TOGGLE=1

# Optional. 1 (default) = render the toggle name on the Claude Code
# statusline when ON. 0 = invisible. Define toggle_<name>_statusline to
# override the rendered fragment (see "Custom statusline" below).
TOGGLE_STATUSLINE=1

# Optional. Each entry is a single string with four fields separated by the
# ASCII unit separator (\x1f). See "Extra enforcement hooks" below.
TOGGLE_EXTRA_HOOKS=()
```

## `<name>.md` — the slash command body

```markdown
---
description: Toggle coauth for this project. User-invokable only.
---
<!-- coauth-toggle-marker -->
The user just typed `/coauth`. The dispatcher already flipped state and announced. Acknowledge in one short line.
```

Two things to know:

- The frontmatter `description` shows up in the slash-command picker. Keep it short.
- The body never has to *implement* the rule. The dispatcher has already flipped state and injected `ON_MSG` or `OFF_MSG` before the model sees the prompt, so the body is a tiny acknowledgement.
- Including `TOGGLE_MARKER` as a comment in the body is the safest invocation signal. Claude Code currently sends `<command-name>/<name></command-name>` in prompts and the dispatcher matches on that, but the marker survives prompt-format changes.

## Scope: pick the right one

| Scope | Sentinel keyed on | Use when |
|---|---|---|
| `global` | nothing | The rule is about you, not a project (e.g. "always log a devlog entry"). |
| `project` | sha256 of the git root, or cwd if not a repo | The rule depends on the repo (e.g. "use Co-Authored-By in this org's repos"). Sub-directories of the same repo share state. |
| `session` | Claude Code session id | The rule lasts only as long as the conversation (e.g. "review every commit before push"). |

**Pitfall:** if you pick `project` but flip the toggle from a directory that isn't a git repo, the sentinel is keyed on the cwd. Run `claudetoggle list` to see the resolved state.

## Idempotency

The dispatcher flips state exactly once per `/<name>` invocation:

- ON to OFF, or OFF to ON. There is no "double on".
- A second `/<name>` in the same prompt is ignored (only the first slash command in a prompt is processed).
- Reannounces never flip state — they only re-inject `ON_MSG` while the toggle is already ON.

Your `<name>.md` body and your peer scripts must be idempotent too: the model should be able to acknowledge or skip with no side effects either way.

## Extra enforcement hooks

Sometimes telling the model "do X" isn't enough — you want a hook that *blocks* the offending action when the toggle is on (or off). Drop a peer script alongside `toggle.sh` and register it:

```sh
TOGGLE_EXTRA_HOOKS=()
TOGGLE_EXTRA_HOOKS+=("PreToolUse"$'\x1f'"Bash"$'\x1f'"Bash(git commit *)"$'\x1f'"check.sh")
```

Each entry is one string, four fields, separator `$'\x1f'` (ASCII unit separator — chosen because it never appears inside Claude Code's `if` clause syntax):

| Field | Example | Meaning |
|---|---|---|
| event | `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`, ... | Any Claude Code hook event. |
| matcher | `Bash`, `Edit`, `Write`, `*` | Which tool calls this hook fires for. |
| if | `Bash(git commit *)` | Optional Claude Code if-clause expression. Empty string means always. |
| script | `check.sh` | Path relative to the toggle's directory. The dispatcher rewrites it to the absolute path under `$CLAUDETOGGLE_HOME/toggles/<name>/<script>` at register time. |

### What a peer script looks like

```sh
#!/usr/bin/env bash
# check.sh — block git commit when coauth is OFF unless the user explicitly
# overrides. Source the framework helpers from the standard XDG location.

CLAUDETOGGLE_LIB=${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "$0")")/../../lib}
. "$CLAUDETOGGLE_LIB/hook_io.sh"
. "$CLAUDETOGGLE_LIB/scope.sh"
. "$CLAUDETOGGLE_LIB/toggle.sh"

input=$(cat)
cwd=$(jq -r '.cwd // ""' <<<"$input")
session=$(jq -r '.session_id // ""' <<<"$input")
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")

if toggle_active project coauth "$cwd" "$session"; then
    # Toggle is ON — let the commit through.
    exit 0
fi

# Toggle is OFF — refuse if the commit message contains a Co-Authored-By trailer.
if [[ $cmd == *"Co-Authored-By"* ]]; then
    deny_pretooluse "coauth is OFF: drop the Co-Authored-By trailer or flip /coauth ON."
fi
exit 0
```

The peer script's two paths:

- `exit 0` — allow the tool call (default).
- `deny_pretooluse "REASON"` — emit the deny JSON and exit 0. Claude Code blocks the call and surfaces REASON to the model.

For richer cases use `deny_with_errors` (see `lib/hook_io.sh`).

## State files: where they live, what's in them

For your own scripts:

- Sentinel: `$CLAUDETOGGLE_HOME/state/<name>/<scope-key>` (a 0-byte file; existence is the whole signal).
- Counter: `$CLAUDETOGGLE_HOME/state/<name>/counter` (one integer, shared across sessions, written under a flock).
- Counter lock: `$CLAUDETOGGLE_HOME/state/<name>/counter.lock`.

Treat the layout as private. Don't poke at sentinels directly — the framework adds a deny rule that prevents the *model* from doing so, and you should follow the same discipline. Use `toggle_on`, `toggle_off`, `toggle_active`, `toggle_tick` and `toggle_seed_counter` from `lib/toggle.sh`.

If you need richer state, store it under `$CLAUDETOGGLE_HOME/state/<name>/extras/...`. The framework will not write or remove anything there; you own it.

## Custom statusline

To override the default statusline fragment (which is just `<name>`), define a function with the exact name `toggle_<name>_statusline` in `toggle.sh`:

```sh
toggle_coauth_statusline() {
    printf 'co✓'
}
```

Constraints:

- Must be fast (it runs once per redraw, inside a subshell).
- Must be side-effect-free.
- Stdout becomes the fragment. Empty stdout suppresses the fragment.

## A complete minimal toggle

```sh
# ~/projects/safetynet/toggle.sh
TOGGLE_API=1
TOGGLE_NAME=safetynet
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="safetynet is ON: refuse git push --force, rm -rf and any irreversible filesystem operation."
TOGGLE_OFF_MSG="safetynet is OFF."
TOGGLE_MARKER="<!-- safetynet-marker -->"
```

```markdown
<!-- ~/projects/safetynet/safetynet.md -->
---
description: Toggle the safety net for this session.
---
<!-- safetynet-marker -->
The user just typed `/safetynet`. State has already flipped. Acknowledge in one short line.
```

```sh
claudetoggle add --dry-run ~/projects/safetynet   # preview
claudetoggle add ~/projects/safetynet             # commit
claudetoggle list
```

## Iterating

After editing a registered toggle's metadata:

```sh
claudetoggle remove <name>
claudetoggle add <path>
```

There is no in-place reload, by design — re-registering forces the deny rules and hook entries in `settings.json` to be regenerated cleanly.

## Things that look easy but bite

- **TOGGLE_NAME mismatch**: the directory, `TOGGLE_NAME`, and `<name>.md` filename must match. The CLI rejects mismatches at `add` time.
- **Project scope without git**: the sentinel is keyed on the cwd, so flipping the toggle from `~/Downloads` and `~/projects/x` produces two separate states.
- **Forgetting `TOGGLE_MARKER`**: the toggle still works in current Claude Code, but a future change to prompt formatting could break invocation detection. Always include a marker.
- **Storing state by hand**: don't write to the sentinel directly from peer scripts. The framework's deny rules block the model from doing it, and your own scripts should use `toggle_on`/`toggle_off` to keep behaviour consistent.
- **Heavy work in the statusline function**: it runs every redraw. Anything more than a few characters of derived text belongs elsewhere.

## Reference

- `lib/toggle.sh` is the canonical schema reference (the header comment lists every variable).
- `lib/hook_io.sh` defines `block_userprompt`, `inject_context`, `deny_pretooluse`, `deny_with_errors`, `hook_log`.
- `lib/scope.sh` defines `scope_path` and `project_key`.
- `examples/coauth/` is a complete worked example with a peer script.
