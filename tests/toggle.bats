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

@test "toggle_files lists registry .sh files" {
	mkdir -p "$TOGGLE_REGISTRY"
	: >"$TOGGLE_REGISTRY/foo.sh"
	: >"$TOGGLE_REGISTRY/bar.sh"
	: >"$TOGGLE_REGISTRY/ignore.txt"
	run toggle_files
	[ "$status" -eq 0 ]
	[[ "$output" == *"/foo.sh"* ]]
	[[ "$output" == *"/bar.sh"* ]]
	[[ "$output" != *"ignore.txt"* ]]
}

@test "toggle_reset clears all TOGGLE_* vars" {
	TOGGLE_NAME=x TOGGLE_SCOPE=session TOGGLE_ON_MSG=on TOGGLE_OFF_MSG=off
	TOGGLE_MARKER=m TOGGLE_REANNOUNCE_EVERY=5
	TOGGLE_ANNOUNCE_ON_SESSION_START=1 TOGGLE_ANNOUNCE_ON_TOGGLE=0
	TOGGLE_STATUSLINE=1
	toggle_reset
	[ -z "${TOGGLE_NAME:-}" ]
	[ -z "${TOGGLE_SCOPE:-}" ]
	[ -z "${TOGGLE_ON_MSG:-}" ]
	[ -z "${TOGGLE_OFF_MSG:-}" ]
	[ -z "${TOGGLE_MARKER:-}" ]
	[ -z "${TOGGLE_REANNOUNCE_EVERY:-}" ]
	[ -z "${TOGGLE_ANNOUNCE_ON_SESSION_START:-}" ]
	[ -z "${TOGGLE_ANNOUNCE_ON_TOGGLE:-}" ]
	[ -z "${TOGGLE_STATUSLINE:-}" ]
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
