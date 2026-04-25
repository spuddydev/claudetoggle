#!/usr/bin/env bash
# coauth peer hook — runs as PreToolUse(Bash) when the model is about to run
# `git commit ...`. Reads the commit message from the tool input and gates
# according to the current coauth toggle state.
#
# This example demonstrates the framework's PreToolUse extension point. It
# enforces the trailer presence/absence rule only; the multi-rule header
# linter from the upstream live system is intentionally trimmed.

set -o pipefail

CLAUDETOGGLE_LIB=${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "$0")")/../../lib}
# shellcheck source=/dev/null
. "$CLAUDETOGGLE_LIB/scope.sh"
# shellcheck source=/dev/null
. "$CLAUDETOGGLE_LIB/hook_io.sh"

INPUT=$(cat)
cwd=$(jq -r '.cwd // ""' <<<"$INPUT")
cmd=$(jq -r '.tool_input.command // ""' <<<"$INPUT")

# Extract the message from -m "..." or -m'...'. If no -m, ignore (the model
# may be using --file or interactive mode; not our concern).
msg=$(printf '%s' "$cmd" | sed -nE 's/.*-m[[:space:]]+(["'\''])(.*)\1.*/\2/p')
[ -n "$msg" ] || exit 0

sentinel=$(scope_path project coauth "$cwd") || exit 0

errors=()
if [ -f "$sentinel" ]; then
	# coauth ON — require the trailer.
	if ! printf '%s' "$msg" | grep -q "Co-Authored-By: Claude"; then
		errors+=("coauth is ON but the commit message lacks a Co-Authored-By: Claude trailer")
	fi
else
	# coauth OFF — refuse a trailer or a multi-line message.
	if printf '%s' "$msg" | grep -q "Co-Authored-By:"; then
		errors+=("coauth is OFF but the commit message includes a Co-Authored-By trailer")
	fi
	if printf '%s' "$msg" | grep -q $'\n'; then
		errors+=("coauth is OFF: keep the commit message on a single conventional header line")
	fi
fi

deny_with_errors "commit message" "command" "$cmd" "${errors[@]}"
