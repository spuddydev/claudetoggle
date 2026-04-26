#!/usr/bin/env bats

load test_helper

setup() {
	setup_isolated_home
	load_lib toggle
}

teardown() {
	teardown_isolated_home
}

@test "toggle_files prints nothing when registry missing" {
	run toggle_files
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "toggle_files lists toggles/<name>/toggle.sh entries, sorted, skipping strays" {
	local reg=$CLAUDETOGGLE_HOME/toggles
	mkdir -p "$reg/foo" "$reg/bar" "$reg/ignored" "$reg/empty"
	: >"$reg/foo/toggle.sh"
	: >"$reg/bar/toggle.sh"
	# Stray: no toggle.sh inside the dir → skipped
	: >"$reg/ignored/notes.txt"
	# Sibling: framework lib dir is a sibling of toggles/, not under it
	mkdir -p "$CLAUDETOGGLE_HOME/lib"
	: >"$CLAUDETOGGLE_HOME/lib/scope.sh"
	run toggle_files
	[ "$status" -eq 0 ]
	expected="$reg/bar/toggle.sh"$'\n'"$reg/foo/toggle.sh"
	[ "$output" = "$expected" ]
}

@test "toggle_reset clears all TOGGLE_* vars" {
	TOGGLE_NAME=x TOGGLE_SCOPE=session TOGGLE_API=1 TOGGLE_ON_MSG=on TOGGLE_OFF_MSG=off
	TOGGLE_MARKER=m TOGGLE_REANNOUNCE_EVERY=5
	TOGGLE_ANNOUNCE_ON_SESSION_START=1 TOGGLE_ANNOUNCE_ON_TOGGLE=0
	TOGGLE_STATUSLINE=1 TOGGLE_EXTRA_HOOKS=("a")
	toggle_reset
	[ -z "${TOGGLE_NAME:-}" ]
	[ -z "${TOGGLE_SCOPE:-}" ]
	[ -z "${TOGGLE_API:-}" ]
	[ -z "${TOGGLE_ON_MSG:-}" ]
	[ -z "${TOGGLE_OFF_MSG:-}" ]
	[ -z "${TOGGLE_MARKER:-}" ]
	[ -z "${TOGGLE_REANNOUNCE_EVERY:-}" ]
	[ -z "${TOGGLE_ANNOUNCE_ON_SESSION_START:-}" ]
	[ -z "${TOGGLE_ANNOUNCE_ON_TOGGLE:-}" ]
	[ -z "${TOGGLE_STATUSLINE:-}" ]
	[ -z "${TOGGLE_EXTRA_HOOKS+set}" ]
}

@test "toggle_active returns 1 when off, 0 when on, 2 when scope unavailable" {
	run toggle_active session feat "" sid
	[ "$status" -eq 1 ]
	run toggle_active session feat "" ""
	[ "$status" -eq 2 ]
	run toggle_active project feat "" "sid"
	[ "$status" -eq 2 ]
	toggle_on session feat "" sid
	run toggle_active session feat "" sid
	[ "$status" -eq 0 ]
}

@test "toggle_on creates the sentinel under .state" {
	toggle_on global feat "" ""
	[ -f "$CLAUDETOGGLE_HOME/state/feat/global" ]
}

@test "toggle_off removes sentinel and counter" {
	toggle_on session feat "" sid
	toggle_seed_counter feat 3
	[ -f "$CLAUDETOGGLE_HOME/state/feat/sessions/sid" ]
	[ -f "$CLAUDETOGGLE_HOME/state/feat/counter" ]
	toggle_off session feat "" sid
	[ ! -f "$CLAUDETOGGLE_HOME/state/feat/sessions/sid" ]
	[ ! -f "$CLAUDETOGGLE_HOME/state/feat/counter" ]
}

@test "toggle_on returns 1 when scope unavailable" {
	run toggle_on project feat "" sid
	[ "$status" -eq 1 ]
}

@test "toggle_tick increments and persists; counter is shared across sessions" {
	one=$(toggle_tick feat)
	two=$(toggle_tick feat)
	three=$(toggle_tick feat)
	[ "$one" = "1" ]
	[ "$two" = "2" ]
	[ "$three" = "3" ]
	[ -f "$CLAUDETOGGLE_HOME/state/feat/counter" ]
}

@test "toggle_tick treats corrupt counter as 0" {
	mkdir -p "$CLAUDETOGGLE_HOME/state/feat"
	printf 'garbage\n' >"$CLAUDETOGGLE_HOME/state/feat/counter"
	got=$(toggle_tick feat)
	[ "$got" = "1" ]
}

@test "toggle_seed_counter sets value, next tick crosses threshold" {
	toggle_seed_counter feat 9
	got=$(toggle_tick feat)
	[ "$got" = "10" ]
}

@test "sentinel and counter live at distinct paths under .state" {
	toggle_on session feat "" sid
	toggle_seed_counter feat 0
	s=$(toggle_sentinel_for session feat "" sid)
	c=$(toggle_counter_for feat)
	[ "$s" != "$c" ]
	[ -f "$s" ]
	[ -f "$c" ]
}

@test "toggle_statusline_fn derives name from toggle name" {
	got=$(toggle_statusline_fn coauth)
	[ "$got" = "toggle_coauth_statusline" ]
}

@test "toggle_on creates sentinel with mode 600" {
	toggle_on global feat "" ""
	mode=$(stat -c '%a' "$CLAUDETOGGLE_HOME/state/feat/global")
	[ "$mode" = "600" ]
}

@test "toggle_tick is serialised under the counter lock (no lost updates)" {
	# Spawn N background ticks that all increment the same counter. Without
	# a lock the read-modify-write would race and the final value would be
	# less than N. With the lock, the final value must equal N.
	local n=20 i pids=()
	for ((i = 0; i < n; i++)); do
		(toggle_tick race >/dev/null) &
		pids+=($!)
	done
	for p in "${pids[@]}"; do wait "$p"; done
	read -r final <"$CLAUDETOGGLE_HOME/state/race/counter"
	[ "$final" = "$n" ]
}
