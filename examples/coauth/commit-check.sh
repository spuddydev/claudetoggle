#!/usr/bin/env bash
# coauth peer hook — runs as PreToolUse(Bash) when the model is about to run
# `git commit ...`. Gates the trailer presence/absence according to the
# current toggle state.
#
# Trailer detection scans the full command rather than an extracted -m
# substring. Heredocs (`-m "$(cat <<EOF ... EOF)"`), --message=, multi-line
# -m strings and -F /tmp/file all defeat single-line regex extraction, so
# we look for the literal trailer wherever it appears in the command. False
# positives (the trailer mentioned in an echo) are accepted as a worthwhile
# trade-off; nobody mentions the trailer outside a real commit.

set -o pipefail

CLAUDETOGGLE_LIB=${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "$0")")/../../lib}
# shellcheck source=/dev/null
. "$CLAUDETOGGLE_LIB/scope.sh"
# shellcheck source=/dev/null
. "$CLAUDETOGGLE_LIB/hook_io.sh"

INPUT=$(cat)
cwd=$(jq -r '.cwd // ""' <<<"$INPUT")
cmd=$(jq -r '.tool_input.command // ""' <<<"$INPUT")

sentinel=$(scope_path project coauth "$cwd" "") || exit 0

has_trailer() {
	printf '%s' "$1" | grep -qF 'Co-Authored-By:'
}

errors=()
if [ -f "$sentinel" ]; then
	# coauth ON — require the trailer somewhere in the commit command.
	has_trailer "$cmd" ||
		errors+=("coauth is ON but the commit message lacks a Co-Authored-By: Claude trailer")
else
	# coauth OFF — refuse the trailer wherever it appears.
	! has_trailer "$cmd" ||
		errors+=("coauth is OFF but the commit message includes a Co-Authored-By trailer")
fi

deny_with_errors "commit message" "command" "$cmd" "${errors[@]}"
