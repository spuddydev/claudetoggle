---
name: create-claudetoggle
description: Scaffold a new claudetoggle toggle. Use when the user wants to create, draft, or generate a new toggle (a /<name> slash-command in Claude Code that flips a rule on and off). Asks 4-5 questions, emits toggle.sh and <name>.md (and optional peer hook script) into a directory the user can review, then prints the exact `claudetoggle add` command to register it.
---

# Create a claudetoggle toggle

You help the user scaffold a new toggle for the [claudetoggle](https://github.com/spuddydev/claudetoggle) framework. A toggle is a `/<name>` slash-command that flips a behavioural rule on and off for Claude Code, scoped to a project, a session, or globally.

## Before you start

Read these files in this order. Do not skip — the framework has a specific schema and getting the metadata wrong silently breaks the toggle.

1. `~/.local/share/claudetoggle/lib/toggle.sh` — the canonical schema header (every TOGGLE_* variable, what it does, what's required vs optional).
2. `~/.local/share/claudetoggle/examples/coauth/` — a complete worked example with a peer hook.
3. The repo's `docs/AUTHORING.md` if available (try `~/.local/share/claudetoggle/docs/AUTHORING.md`, or fetch from the GitHub repo if missing locally).

If `~/.local/share/claudetoggle` doesn't exist, the user has not installed claudetoggle yet. Tell them:

```
curl -sSfL https://raw.githubusercontent.com/spuddydev/claudetoggle/main/setup.sh | sh
```

and stop.

## Gather requirements

Ask the user (in one message — do not interrogate one question at a time):

1. **Name** — short, lowercase, dashes only, no underscores. This becomes `/<name>`.
2. **What it does** — one sentence. You'll turn this into the ON message.
3. **Scope** — project (per-repo, persists across sessions), session (this conversation only), or global (everywhere)?
4. **Reannounce** — does the rule fade from the model's mind on long conversations? If yes, suggest `TOGGLE_REANNOUNCE_EVERY=10` or similar.
5. **Enforcement** — does the rule need a hook script that *blocks* a tool call when violated, or is "telling the model" enough? If a hook is needed, ask which event and which tool (e.g. `PreToolUse` on `Bash` for `git commit *`).

Make reasonable defaults if the user says "you pick". Reasonable defaults:

- Scope: `session` if the user is unsure (lowest blast radius).
- Reannounce: `0` unless the rule is short enough to fit in a one-liner, in which case `10`.
- Enforcement: none — start with model-only, the user can iterate.

## Generate the files

Pick a target directory (default `~/projects/<name>` — confirm with the user). Write three files:

### `<dir>/toggle.sh`

Use this template. Fill in the user's answers. Keep `TOGGLE_API=1`, always include `TOGGLE_MARKER`, omit any optional variables you don't need:

```sh
# <name> — <one-sentence description>.
#
# shellcheck disable=SC2034
# All TOGGLE_* vars are read by the dispatcher when this file is sourced.

TOGGLE_API=1
TOGGLE_NAME=<name>
TOGGLE_SCOPE=<global|project|session>

TOGGLE_ON_MSG="<name> is ON: <imperative instruction the model can follow>."
TOGGLE_OFF_MSG="<name> is OFF: <what the absence of the rule means>."

TOGGLE_MARKER="<!-- <name>-toggle-marker -->"
# Only include this line if the user asked for periodic reannouncement.
# TOGGLE_REANNOUNCE_EVERY=10

# Only include the next two lines if the user asked for an enforcement hook.
# TOGGLE_EXTRA_HOOKS=()
# TOGGLE_EXTRA_HOOKS+=("PreToolUse"$'\x1f'"Bash"$'\x1f'"Bash(<command pattern>)"$'\x1f'"<peer-script>.sh")
```

Compose the ON and OFF messages as **complete instructions to the model**, not chat to the user. Examples:

- Good ON: `"safetynet is ON: refuse git push --force, rm -rf and any irreversible filesystem operation. Ask the user to flip /safetynet OFF if they really want it."`
- Bad ON: `"Safety net activated."` (the model does not know what to do with this).

### `<dir>/<name>.md`

```markdown
---
description: Toggle <name> for this <scope>.
---
<!-- <name>-toggle-marker -->
The user just typed `/<name>`. The dispatcher already flipped state and announced. Acknowledge in one short line.
```

### `<dir>/<peer-script>.sh` (only if the user asked for enforcement)

```sh
#!/usr/bin/env bash
# <peer-script>.sh — peer hook for <name>.

CLAUDETOGGLE_LIB=${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "$0")")/../../lib}
. "$CLAUDETOGGLE_LIB/hook_io.sh"
. "$CLAUDETOGGLE_LIB/scope.sh"
. "$CLAUDETOGGLE_LIB/toggle.sh"

input=$(cat)
cwd=$(jq -r '.cwd // ""' <<<"$input")
session=$(jq -r '.session_id // ""' <<<"$input")
# Read the tool input field that's relevant for your matcher.
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")

# Branch on whether the toggle is ON or OFF.
if toggle_active <scope> <name> "$cwd" "$session"; then
    # Toggle is ON — your enforcement logic here.
    : # exit 0 (allow) or call deny_pretooluse "REASON"
else
    # Toggle is OFF — usually allow.
    exit 0
fi
exit 0
```

`chmod +x <dir>/<peer-script>.sh` after writing.

## Validate before registering

Run a syntax check on every `.sh` you wrote:

```sh
bash -n <dir>/toggle.sh
bash -n <dir>/<peer-script>.sh    # if any
```

If `claudetoggle` is on PATH, dry-run the registration:

```sh
claudetoggle add --dry-run <dir>
```

That prints exactly what would change in `settings.json` and on disk, without writing. Surface the output to the user verbatim.

## Hand off to the user

End by printing the exact command the user runs to register:

```sh
claudetoggle add <dir>
```

**Do not run it yourself.** The user is responsible for review and registration. Make this clear.

After they register, suggest:

```sh
claudetoggle list             # confirms the new toggle
/<name>                       # in Claude Code, flips it on
```

## Things that bite

- **Underscores in the name** — Claude Code slash commands disallow underscores. Use dashes.
- **Mismatched names** — directory name, `TOGGLE_NAME` and `<name>.md` filename must all match exactly. The CLI rejects mismatches at `add` time, but catch it earlier by being careful.
- **Project scope without git** — the sentinel is keyed on cwd if there's no repo. Mention this to the user if they pick `project`.
- **Heavy logic in `<name>.md`** — the dispatcher already flipped state and injected the message before the model reads the body. Keep the body trivial.
- **Forgetting `TOGGLE_MARKER`** — always include it. Tiny insurance against future Claude Code prompt-format changes.
- **Peer-script paths** — must be relative to the toggle directory in `TOGGLE_EXTRA_HOOKS`, not absolute. The CLI rewrites them to absolute paths under `$CLAUDETOGGLE_HOME/toggles/<name>/<script>` at register time.

## When NOT to use this skill

- The user wants to *modify* an existing toggle — they should `claudetoggle remove <name>` and `claudetoggle add <path>` after editing the source. No skill needed.
- The user wants to debug a toggle — point them at `claudetoggle doctor` and `CLAUDETOGGLE_DEBUG=1`.
- The user wants to write a hook unrelated to toggles — this skill is wrong; they want raw Claude Code hooks in `settings.json`.
