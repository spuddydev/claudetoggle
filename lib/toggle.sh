#!/usr/bin/env bash
# Toggle registry.
#
# Each toggle lives at $TOGGLE_REGISTRY/<name>.sh and declares:
#
#   TOGGLE_NAME                       short name (must match filename stem)
#   TOGGLE_SCOPE                      "global", "project" or "session"
#   TOGGLE_ON_MSG                     full rule text shown to the model when ON
#   TOGGLE_OFF_MSG                    (optional) text shown when toggled OFF
#   TOGGLE_MARKER                     (optional) substring in the slash-command body
#   TOGGLE_REANNOUNCE_EVERY           (optional, default 0) re-inject ON_MSG every N prompts
#   TOGGLE_ANNOUNCE_ON_SESSION_START  (optional, default 0) print ON_MSG at SessionStart
#   TOGGLE_ANNOUNCE_ON_TOGGLE         (optional, default 1) block prompt and announce on flip
#   TOGGLE_STATUSLINE                 (optional, default 1) show name in statusline when ON
#   TOGGLE_STATUSLINE_FN              (optional) function name returning a custom statusline
#                                     fragment for this toggle (when ON). Receives no args.
#
# That is the whole interface. The dispatcher and statusline iterate over
# every file in the registry; adding a new toggle is just dropping a file
# here and a matching commands/<name>.md.

# Source order matters: scope.sh provides scope_path, used below.
# Resolve symlinks so this works whether install.sh symlinks the whole
# lib/ directory or each file individually. The CLAUDETOGGLE_LIB override
# lets a non-standard install point at the lib dir explicitly.
# shellcheck source=lib/scope.sh
. "${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")}/scope.sh"

TOGGLE_REGISTRY=${TOGGLE_REGISTRY:-$HOME/.claude/toggles}

# Reannounce counters live under <feature>/counters/<sid>, deliberately
# separate from <feature>/sessions/<sid> so a session-scoped sentinel
# (a file) and the counter (also a file) cannot collide on the same path.

# toggle_files → print every registered toggle file path on its own line.
# Silent when the registry is missing or empty so callers can pipe safely.
toggle_files() {
	[ -d "$TOGGLE_REGISTRY" ] || return 0
	local f
	for f in "$TOGGLE_REGISTRY"/*.sh; do
		[ -r "$f" ] && printf '%s\n' "$f"
	done
}

# toggle_reset → unset every TOGGLE_* var so the next source starts clean.
# Call between toggles when iterating the registry in one shell.
toggle_reset() {
	unset TOGGLE_NAME TOGGLE_SCOPE TOGGLE_ON_MSG TOGGLE_OFF_MSG TOGGLE_MARKER \
		TOGGLE_REANNOUNCE_EVERY TOGGLE_ANNOUNCE_ON_SESSION_START \
		TOGGLE_ANNOUNCE_ON_TOGGLE TOGGLE_STATUSLINE
}

# toggle_sentinel_for SCOPE NAME CWD SESSION → print the sentinel path or
# nothing (and return 1) if the required scope key is missing.
toggle_sentinel_for() {
	scope_path "$1" "$2" "$3" "$4"
}

# toggle_counter_for NAME SESSION → per-session reannounce counter path.
# Always session-scoped: two concurrent sessions in the same project must
# not race the counter, and global toggles still want per-session cadence.
toggle_counter_for() {
	[ -n "$2" ] || return 1
	printf '%s\n' "${CLAUDETOGGLE_HOME:-$HOME/.claude}/$1/counters/$2"
}

# toggle_active SCOPE NAME CWD SESSION → 0 if ON, 1 if OFF, 2 if the
# scope key is unavailable (e.g. project toggle with no CWD). Distinct
# codes so the dispatcher can skip silently rather than treating an
# unavailable scope as OFF and wrongly flipping it.
toggle_active() {
	local sentinel
	sentinel=$(toggle_sentinel_for "$1" "$2" "$3" "$4") || return 2
	[ -f "$sentinel" ]
}

# toggle_on SCOPE NAME CWD SESSION → flip ON: ensure parent dir, touch
# the sentinel. Returns 1 if scope key is unavailable.
toggle_on() {
	local sentinel
	sentinel=$(toggle_sentinel_for "$1" "$2" "$3" "$4") || return 1
	mkdir -p "${sentinel%/*}"
	: >"$sentinel"
}

# toggle_off SCOPE NAME CWD SESSION → flip OFF: remove sentinel and any
# session reannounce counter. Returns 1 if scope key is unavailable.
toggle_off() {
	local sentinel counter
	sentinel=$(toggle_sentinel_for "$1" "$2" "$3" "$4") || return 1
	rm -f "$sentinel"
	counter=$(toggle_counter_for "$2" "$4") && rm -f "$counter"
	return 0
}

# toggle_tick NAME SESSION → increment the per-session reannounce
# counter and print the new value. Returns 1 if no session id.
toggle_tick() {
	local counter count=0
	counter=$(toggle_counter_for "$1" "$2") || return 1
	[ -r "$counter" ] && read -r count <"$counter"
	case $count in '' | *[!0-9]*) count=0 ;; esac
	count=$((count + 1))
	mkdir -p "${counter%/*}"
	printf '%s\n' "$count" >"$counter"
	printf '%s\n' "$count"
}

# toggle_seed_counter NAME SESSION VALUE → set the counter to VALUE so
# the next tick crosses the reannounce threshold. Used right after a
# flip-to-ON to surface ON_MSG on the next ordinary prompt.
toggle_seed_counter() {
	local counter
	counter=$(toggle_counter_for "$1" "$2") || return 1
	mkdir -p "${counter%/*}"
	printf '%s\n' "$3" >"$counter"
}

# toggle_statusline_fn NAME → naming convention for an optional custom
# statusline fragment function. Toggle authors declare a function with
# this exact name in their registry file; the statusline derives the
# name rather than trusting a user-supplied string, so two toggles
# cannot clobber each other.
toggle_statusline_fn() {
	printf 'toggle_%s_statusline\n' "$1"
}
