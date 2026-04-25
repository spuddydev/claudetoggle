#!/usr/bin/env bats

load test_helper

setup() {
	setup_isolated_home
	export TOGGLE_REGISTRY="$CLAUDETOGGLE_HOME/toggles"
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

@test "toggle_files lists <name>/toggle.sh entries, sorted, skipping strays" {
	mkdir -p "$TOGGLE_REGISTRY/foo" "$TOGGLE_REGISTRY/bar" \
		"$TOGGLE_REGISTRY/ignored" "$TOGGLE_REGISTRY/empty"
	: >"$TOGGLE_REGISTRY/foo/toggle.sh"
	: >"$TOGGLE_REGISTRY/bar/toggle.sh"
	# Stray: no toggle.sh inside the dir → skipped
	: >"$TOGGLE_REGISTRY/ignored/notes.txt"
	# Stray: top-level .sh file → skipped (not under a sub-directory)
	: >"$TOGGLE_REGISTRY/loose.sh"
	run toggle_files
	[ "$status" -eq 0 ]
	expected="$TOGGLE_REGISTRY/bar/toggle.sh"$'\n'"$TOGGLE_REGISTRY/foo/toggle.sh"
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
	# Off
	run toggle_active session feat "" sid
	[ "$status" -eq 1 ]
	# Scope unavailable
	run toggle_active session feat "" ""
	[ "$status" -eq 2 ]
	run toggle_active project feat "" "sid"
	[ "$status" -eq 2 ]
	# On
	toggle_on session feat "" sid
	run toggle_active session feat "" sid
	[ "$status" -eq 0 ]
}

@test "toggle_on creates the sentinel" {
	toggle_on global feat "" ""
	[ -f "$CLAUDETOGGLE_HOME/feat/global" ]
}

@test "toggle_off removes sentinel and counter" {
	toggle_on session feat "" sid
	toggle_seed_counter feat sid 3
	[ -f "$CLAUDETOGGLE_HOME/feat/sessions/sid" ]
	[ -f "$CLAUDETOGGLE_HOME/feat/counters/sid" ]
	toggle_off session feat "" sid
	[ ! -f "$CLAUDETOGGLE_HOME/feat/sessions/sid" ]
	[ ! -f "$CLAUDETOGGLE_HOME/feat/counters/sid" ]
}

@test "toggle_on returns 1 when scope unavailable" {
	run toggle_on project feat "" sid
	[ "$status" -eq 1 ]
}

@test "toggle_tick increments and persists" {
	one=$(toggle_tick feat sid)
	two=$(toggle_tick feat sid)
	three=$(toggle_tick feat sid)
	[ "$one" = "1" ]
	[ "$two" = "2" ]
	[ "$three" = "3" ]
	[ -f "$CLAUDETOGGLE_HOME/feat/counters/sid" ]
}

@test "toggle_tick treats corrupt counter as 0" {
	mkdir -p "$CLAUDETOGGLE_HOME/feat/counters"
	printf 'garbage\n' >"$CLAUDETOGGLE_HOME/feat/counters/sid"
	got=$(toggle_tick feat sid)
	[ "$got" = "1" ]
}

@test "toggle_tick fails without session" {
	run toggle_tick feat ""
	[ "$status" -eq 1 ]
}

@test "toggle_seed_counter sets value, next tick crosses threshold" {
	toggle_seed_counter feat sid 9
	got=$(toggle_tick feat sid)
	[ "$got" = "10" ]
}

@test "sentinel and counter never collide for session scope" {
	toggle_on session feat "" sid
	toggle_seed_counter feat sid 0
	[ -f "$CLAUDETOGGLE_HOME/feat/sessions/sid" ]
	[ -f "$CLAUDETOGGLE_HOME/feat/counters/sid" ]
	# The two paths must be distinct files, never the same path.
	s=$(toggle_sentinel_for session feat "" sid)
	c=$(toggle_counter_for feat sid)
	[ "$s" != "$c" ]
}

@test "toggle_statusline_fn derives name from toggle name" {
	got=$(toggle_statusline_fn coauth)
	[ "$got" = "toggle_coauth_statusline" ]
}
