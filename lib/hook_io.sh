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
	local home=${CLAUDETOGGLE_HOME:-$HOME/.claude}
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
