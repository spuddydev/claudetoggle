#!/usr/bin/env bash
# Statusline integration for claudetoggle.
#
# Sourceable only. Defines exactly one function: claudetoggle_statusline.
# Sourcing has no other side effects, and sourcing twice is idempotent.
#
# Usage from a host statusline script:
#
#   . "$HOME/.claudetoggle/bin/statusline.sh"
#   export CLAUDE_CWD="$cwd" CLAUDE_SESSION_ID="$session"
#   left+="$(claudetoggle_statusline)"
#
# Output: nothing when no toggle is active. When any toggle is active, a
# leading separator (U+2502 with regular spaces by default to match the
# common Claude Code statusline) is emitted before the joined names so the
# host can append the result unconditionally without growing custom logic.
#
# Custom toggle_<name>_statusline functions: a registry file may define a
# function named exactly toggle_<name>_statusline; if defined and the toggle
# is active, the function's stdout replaces the default name fragment. Such
# functions MUST be fast and side-effect-free; they run inside a subshell
# per toggle on every redraw.

CLAUDETOGGLE_LIB=${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.lib}
# shellcheck source=lib/scope.sh
. "$CLAUDETOGGLE_LIB/scope.sh"
# shellcheck source=lib/toggle.sh
. "$CLAUDETOGGLE_LIB/toggle.sh"

CLAUDETOGGLE_STATUSLINE_SEP=${CLAUDETOGGLE_STATUSLINE_SEP:- │ }

claudetoggle_statusline() {
	local f frags=() frag cwd=${CLAUDE_CWD:-} sid=${CLAUDE_SESSION_ID:-}
	while IFS= read -r f; do
		# Subshell so each toggle's TOGGLE_* vars and any custom
		# toggle_<name>_statusline function are isolated.
		frag=$(
			# shellcheck disable=SC1090
			. "$f"
			[ "${TOGGLE_API:-}" = "1" ] || exit 0
			[ "${TOGGLE_STATUSLINE:-1}" != "0" ] || exit 0
			toggle_active "$TOGGLE_SCOPE" "$TOGGLE_NAME" "$cwd" "$sid" || exit 0
			fn=$(toggle_statusline_fn "$TOGGLE_NAME")
			if declare -F "$fn" >/dev/null 2>&1; then
				"$fn"
			else
				printf '%s' "$TOGGLE_NAME"
			fi
		)
		[ -n "$frag" ] && frags+=("$frag")
	done < <(toggle_files)
	[ "${#frags[@]}" -eq 0 ] && return 0
	local out=""
	for frag in "${frags[@]}"; do
		out+="${CLAUDETOGGLE_STATUSLINE_SEP}${frag}"
	done
	printf '%s' "$out"
}
