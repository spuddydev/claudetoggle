#!/usr/bin/env bash
# Shared output helpers for Claude Code hooks.
#
# These are tiny on purpose: each helper prints one well-formed JSON
# document to stdout (or appends to a debug log) and exits where
# appropriate. Hooks that need richer behaviour can compose them.

# hook_log MESSAGE...
#   Append a timestamped line to $CLAUDETOGGLE_HOME/hooks-debug.log when
#   CLAUDETOGGLE_DEBUG is set. Cheap no-op otherwise.
hook_log() {
	[ -n "${CLAUDETOGGLE_DEBUG:-}" ] || return 0
	local home=${CLAUDETOGGLE_HOME:-$HOME/.claudetoggle}
	mkdir -p "$home" 2>/dev/null || return 0
	printf '[%s] %s\n' "${EPOCHSECONDS:-$(date +%s)}" "$*" \
		>>"$home/hooks-debug.log" 2>/dev/null || true
}

# block_userprompt REASON
#   Emit a UserPromptSubmit decision that blocks the prompt and shows the
#   reason to the user, then exits. The reason is also injected into the
#   model's context for the next turn.
block_userprompt() {
	jq -n --arg r "$1" '{decision:"block", reason:$r}'
	exit 0
}

# inject_context MESSAGE
#   Add MESSAGE as additional context for the next model turn without
#   blocking the prompt or surfacing a UI notice.
inject_context() {
	jq -n --arg c "$1" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$c}}'
}

# deny_pretooluse REASON
#   Emit a PreToolUse deny JSON with the given reason and exit 0. Use from
#   any PreToolUse hook script that wants to block a tool call.
deny_pretooluse() {
	jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
	exit 0
}

# deny_with_errors LABEL TAIL_LABEL TAIL_VALUE ERRORS...
#   Build a multi-line reason starting "<LABEL> rejected:" followed by
#   bullet-formatted ERRORS, then a blank line and "<TAIL_LABEL>: <TAIL_VALUE>"
#   for the offending input. Calls deny_pretooluse (which exits) when there
#   are any errors. No-op when ERRORS is empty.
deny_with_errors() {
	local label=$1 tail_label=$2 tail_value=$3
	shift 3
	[ "$#" -eq 0 ] && return 0
	local reason="$label rejected:"$'\n' e
	for e in "$@"; do reason+="  • $e"$'\n'; done
	reason+=$'\n'"$tail_label: $tail_value"
	deny_pretooluse "$reason"
}
