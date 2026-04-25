#!/usr/bin/env bash
# coauth — flip the Co-Authored-By: Claude trailer policy for the current
# project. Per-project state, persists across sessions.
#
# shellcheck disable=SC2034
# All TOGGLE_* vars are read by the dispatcher when this file is sourced.

TOGGLE_API=1
TOGGLE_NAME=coauth
TOGGLE_SCOPE=project

TOGGLE_ON_MSG="coauth is ON for this project — include a Co-Authored-By: Claude <noreply@anthropic.com> trailer on any commit you compose this turn (blank line before the trailer; body allowed; conventional header still <=50 characters)."
TOGGLE_OFF_MSG="coauth is OFF for this project — strict mode: no Co-Authored-By trailer; no body; single-line conventional header <=50 characters."

TOGGLE_MARKER="<!-- coauth-toggle-marker -->"
TOGGLE_REANNOUNCE_EVERY=10
TOGGLE_ANNOUNCE_ON_SESSION_START=1

TOGGLE_EXTRA_HOOKS=()
TOGGLE_EXTRA_HOOKS+=("PreToolUse"$'\x1f'"Bash"$'\x1f'"Bash(git commit *)"$'\x1f'"commit-check.sh")
