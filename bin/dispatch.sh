#!/usr/bin/env bash
# Generic dispatcher for claudetoggle.
#
# One settings.json hook entry per event drives every registered toggle:
#   bash "$HOME/.claudetoggle/bin/dispatch.sh" UserPromptSubmit
#   bash "$HOME/.claudetoggle/bin/dispatch.sh" SessionStart
#
# UserPromptSubmit: detect a slash-command toggle invocation; on a match,
# flip the sentinel and announce. With no match, tick reannounce counters
# for active toggles and emit any due reannouncements as a single
# additional-context injection.
#
# SessionStart: emit each active toggle's ON_MSG to stdout (Claude Code
# injects stdout text directly for SessionStart) when ANNOUNCE_ON_SESSION_START
# is non-zero.
#
# Settings.json command strings are shell-parsed (verified live: existing
# entries expand $HOME), so positional args work and any "# claudetoggle:..."
# comment in the command field is a real shell comment at execution time.

set -o pipefail

# Locale-stable glob ordering and sort.
export LC_ALL=C

# Resolve framework lib regardless of whether install.sh symlinks lib/ as a
# whole directory or pieces individually. Override with CLAUDETOGGLE_LIB.
CLAUDETOGGLE_LIB=${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "$0")")/../lib}

# shellcheck source=lib/scope.sh
. "$CLAUDETOGGLE_LIB/scope.sh"
# shellcheck source=lib/toggle.sh
. "$CLAUDETOGGLE_LIB/toggle.sh"
# shellcheck source=lib/command_call.sh
. "$CLAUDETOGGLE_LIB/command_call.sh"
# shellcheck source=lib/hook_io.sh
. "$CLAUDETOGGLE_LIB/hook_io.sh"

INPUT=$(cat)

# Event resolution: argv first (set in settings.json), then JSON fallback for
# tests and direct invocation.
event=${1:-}
if [ -z "$event" ]; then
	event=$(jq -r '.hook_event_name // ""' <<<"$INPUT")
fi
cwd=$(jq -r '.cwd // ""' <<<"$INPUT")
session=$(jq -r '.session_id // ""' <<<"$INPUT")
prompt=$(jq -r '.prompt // ""' <<<"$INPUT")

# api_ok → 0 if TOGGLE_API is exactly "1", else 1. Caller decides what to do.
api_ok() { [ "${TOGGLE_API:-}" = "1" ]; }

# Pass 1 — UserPromptSubmit only: find a toggle whose slash-command was just
# invoked, flip it, and announce. Returns 0 (handled) or 1 (no match).
handle_user_prompt_match() {
	local f
	while IFS= read -r f; do
		toggle_reset
		# shellcheck disable=SC1090
		. "$f"
		if ! api_ok; then
			hook_log "dispatch: api reject $f (api=${TOGGLE_API:-<unset>})"
			continue
		fi
		# Cheap pre-filter: skip command_called when toggle is OFF and the
		# prompt does not mention /name or marker. Saves N forks on most
		# ordinary prompts.
		local active_rc=0 want=0
		toggle_active "$TOGGLE_SCOPE" "$TOGGLE_NAME" "$cwd" "$session" || active_rc=$?
		if [ "$active_rc" -ne 0 ]; then
			[[ $prompt == *"/$TOGGLE_NAME"* ]] && want=1
			[ -n "${TOGGLE_MARKER:-}" ] && [[ $prompt == *"$TOGGLE_MARKER"* ]] && want=1
			[ "$want" -eq 0 ] && continue
		fi

		if ! command_called "$prompt" "$TOGGLE_NAME" "${TOGGLE_MARKER:-}"; then
			continue
		fi

		# Match. Flip per current state.
		case $active_rc in
		0) # currently ON → flip OFF
			toggle_off "$TOGGLE_SCOPE" "$TOGGLE_NAME" "$cwd" "$session"
			msg=${TOGGLE_OFF_MSG:-"$TOGGLE_NAME OFF"}
			;;
		1) # currently OFF → flip ON, optionally seed counter
			toggle_on "$TOGGLE_SCOPE" "$TOGGLE_NAME" "$cwd" "$session"
			if [ "${TOGGLE_REANNOUNCE_EVERY:-0}" -gt 0 ]; then
				toggle_seed_counter "$TOGGLE_NAME" \
					$((TOGGLE_REANNOUNCE_EVERY - 1))
			fi
			msg=${TOGGLE_ON_MSG:-"$TOGGLE_NAME ON"}
			;;
		2) # scope key unavailable; user explicitly invoked the command
			block_userprompt "claudetoggle: /$TOGGLE_NAME requires a $TOGGLE_SCOPE context"
			;;
		esac

		if [ "${TOGGLE_ANNOUNCE_ON_TOGGLE:-1}" != "0" ]; then
			block_userprompt "$msg"
		fi
		# Silent toggle: flip done, no announcement, return.
		return 0
	done < <(toggle_files)
	return 1
}

# Pass 2 — UserPromptSubmit only: tick reannounce counters for every active
# toggle whose REANNOUNCE_EVERY > 0, aggregate due ON_MSGs into one buffer,
# emit a single inject_context if any are due.
handle_reannounce() {
	local f msgs=() count active_rc
	while IFS= read -r f; do
		toggle_reset
		# shellcheck disable=SC1090
		. "$f"
		api_ok || continue
		active_rc=0
		toggle_active "$TOGGLE_SCOPE" "$TOGGLE_NAME" "$cwd" "$session" || active_rc=$?
		[ "$active_rc" -eq 0 ] || continue
		[ "${TOGGLE_REANNOUNCE_EVERY:-0}" -gt 0 ] || continue
		count=$(toggle_tick "$TOGGLE_NAME") || continue
		if [ "$count" -ge "${TOGGLE_REANNOUNCE_EVERY:-0}" ]; then
			msgs+=("$TOGGLE_ON_MSG")
			toggle_seed_counter "$TOGGLE_NAME" 0
		fi
	done < <(toggle_files)
	if [ "${#msgs[@]}" -gt 0 ]; then
		local combined
		combined=$(printf '%s\n\n' "${msgs[@]}")
		inject_context "$combined"
	fi
}

# SessionStart: print active toggles' ON_MSGs to stdout for direct injection.
handle_session_start() {
	local f buf="" active_rc
	while IFS= read -r f; do
		toggle_reset
		# shellcheck disable=SC1090
		. "$f"
		api_ok || continue
		[ "${TOGGLE_ANNOUNCE_ON_SESSION_START:-1}" != "0" ] || continue
		active_rc=0
		toggle_active "$TOGGLE_SCOPE" "$TOGGLE_NAME" "$cwd" "$session" || active_rc=$?
		[ "$active_rc" -eq 0 ] || continue
		buf+="${TOGGLE_ON_MSG}"$'\n\n'
	done < <(toggle_files)
	if [ -n "$buf" ]; then
		printf '%s' "$buf"
	fi
}

case $event in
UserPromptSubmit)
	if handle_user_prompt_match; then
		exit 0
	fi
	handle_reannounce
	;;
SessionStart)
	handle_session_start
	;;
*)
	hook_log "dispatch: unknown event '$event'"
	;;
esac
exit 0
