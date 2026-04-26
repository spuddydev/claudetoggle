#!/usr/bin/env bash
# Toggle registry.
#
# Each toggle lives at $CLAUDETOGGLE_HOME/<name>/toggle.sh and declares:
#
#   TOGGLE_API                        schema version (only "1" accepted)
#   TOGGLE_NAME                       short name (must match directory name)
#   TOGGLE_SCOPE                      "global", "project" or "session"
#   TOGGLE_ON_MSG                     full rule text shown to the model when ON
#   TOGGLE_OFF_MSG                    (optional) text shown when toggled OFF
#   TOGGLE_MARKER                     (optional) substring in the slash-command body
#   TOGGLE_REANNOUNCE_EVERY           (optional, default 0) re-inject ON_MSG every N prompts
#   TOGGLE_ANNOUNCE_ON_SESSION_START  (optional, default 1) print ON_MSG at SessionStart
#   TOGGLE_ANNOUNCE_ON_TOGGLE         (optional, default 1) block prompt and announce on flip
#   TOGGLE_STATUSLINE                 (optional, default 1) show name in statusline when ON
#   TOGGLE_EXTRA_HOOKS                (optional) array of extra event hooks installed alongside
#
# A registry file may also define a function `toggle_<name>_statusline`
# to override the default statusline fragment when ON.
#
# That is the whole interface. The dispatcher and statusline iterate over
# every directory in $CLAUDETOGGLE_HOME (excluding dotted siblings like
# .lib, .bin, .state) and source toggle.sh from each.

# Resolve symlinks so this works whether install.sh symlinks lib/ as a
# whole directory or each file individually. The CLAUDETOGGLE_LIB override
# lets a non-standard install point at the lib dir explicitly.
# shellcheck source=lib/scope.sh
. "${CLAUDETOGGLE_LIB:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")}/scope.sh"

# toggle_files → print every registered toggle file path on its own line.
# Layout: $CLAUDETOGGLE_HOME/<name>/toggle.sh. Default bash glob skips
# dotted directories so .lib, .bin and .state are naturally excluded.
# Output is sorted under LC_ALL=C so ordering is reproducible across
# locales. Silent when the registry is empty so callers can pipe.
toggle_files() {
	[ -d "$CLAUDETOGGLE_HOME" ] || return 0
	local f found=()
	for f in "$CLAUDETOGGLE_HOME"/*/toggle.sh; do
		[ -r "$f" ] && found+=("$f")
	done
	[ "${#found[@]}" -eq 0 ] && return 0
	printf '%s\n' "${found[@]}" | LC_ALL=C sort
}

# toggle_reset → unset every TOGGLE_* var so the next source starts clean.
# Call between toggles when iterating the registry in one shell.
toggle_reset() {
	unset TOGGLE_NAME TOGGLE_SCOPE TOGGLE_API TOGGLE_ON_MSG TOGGLE_OFF_MSG \
		TOGGLE_MARKER TOGGLE_REANNOUNCE_EVERY TOGGLE_ANNOUNCE_ON_SESSION_START \
		TOGGLE_ANNOUNCE_ON_TOGGLE TOGGLE_STATUSLINE TOGGLE_EXTRA_HOOKS
}

# toggle_sentinel_for SCOPE NAME CWD SESSION → print the sentinel path or
# nothing (and return 1) if the required scope key is missing.
toggle_sentinel_for() {
	scope_path "$1" "$2" "$3" "$4"
}

# toggle_counter_for NAME → single shared reannounce counter for this
# toggle. One counter across all sessions; reannounces fire on the global
# tick budget rather than independently per session.
toggle_counter_for() {
	printf '%s\n' "$CLAUDETOGGLE_HOME/.state/$1/counter"
}

# toggle_active SCOPE NAME CWD SESSION → 0 if ON, 1 if OFF, 2 if the
# scope key is unavailable (e.g. project toggle with no CWD).
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

# toggle_off SCOPE NAME CWD SESSION → flip OFF: remove sentinel and the
# shared reannounce counter. Returns 1 if scope key is unavailable.
toggle_off() {
	local sentinel
	sentinel=$(toggle_sentinel_for "$1" "$2" "$3" "$4") || return 1
	rm -f "$sentinel"
	rm -f "$(toggle_counter_for "$2")"
}

# toggle_tick NAME → increment the shared reannounce counter and print
# the new value.
toggle_tick() {
	local counter count=0
	counter=$(toggle_counter_for "$1")
	[ -r "$counter" ] && read -r count <"$counter"
	case $count in '' | *[!0-9]*) count=0 ;; esac
	count=$((count + 1))
	mkdir -p "${counter%/*}"
	printf '%s\n' "$count" >"$counter"
	printf '%s\n' "$count"
}

# toggle_seed_counter NAME VALUE → set the counter to VALUE so the next
# tick crosses the reannounce threshold. Used right after a flip-to-ON
# to surface ON_MSG on the next ordinary prompt.
toggle_seed_counter() {
	local counter
	counter=$(toggle_counter_for "$1")
	mkdir -p "${counter%/*}"
	printf '%s\n' "$2" >"$counter"
}

# toggle_statusline_fn NAME → naming convention for an optional custom
# statusline fragment function. Toggle authors declare a function with
# this exact name in their registry file; the statusline derives the
# name rather than trusting a user-supplied string, so two toggles
# cannot clobber each other.
toggle_statusline_fn() {
	printf 'toggle_%s_statusline\n' "$1"
}
