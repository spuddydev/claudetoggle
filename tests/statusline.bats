#!/usr/bin/env bats

load test_helper

write_toggle() {
	local name=$1 scope=$2 extra=${3:-}
	mkdir -p "$CLAUDETOGGLE_HOME/$name"
	cat >"$CLAUDETOGGLE_HOME/$name/toggle.sh" <<EOF
TOGGLE_API=1
TOGGLE_NAME=$name
TOGGLE_SCOPE=$scope
TOGGLE_ON_MSG="$name on"
TOGGLE_OFF_MSG="$name off"
$extra
EOF
}

# Source statusline.sh in a subshell with isolated env, then call the function
# and capture stdout. Avoids leaking statusline state into bats internals.
sl() {
	# Use ${var-default} (no colon) so callers can pass empty string for cwd
	# or sid to force a scope-unavailable code path.
	local cwd=${1-$CWD} sid=${2-$SID}
	bash -c '
        export CLAUDETOGGLE_HOME="$1" CLAUDETOGGLE_LIB="$5/lib"
        export CLAUDE_CWD="$2" CLAUDE_SESSION_ID="$3"
        . "$5/bin/statusline.sh"
        claudetoggle_statusline
    ' _ "$CLAUDETOGGLE_HOME" "$cwd" "$sid" "" "$(repo_root)"
}

setup() {
	setup_isolated_home
	export CWD="$BATS_TEST_TMPDIR/cwd" SID=s1
	mkdir -p "$CWD"
	export LC_ALL=C
}

teardown() {
	teardown_isolated_home
}

@test "no toggles registered → empty" {
	mkdir -p "$CLAUDETOGGLE_HOME"
	got=$(sl)
	[ -z "$got" ]
}

@test "single active toggle prints leading separator and name" {
	write_toggle foo session
	# Activate by touching the sentinel directly via the lib.
	. "$(repo_root)/lib/toggle.sh"
	toggle_on session foo "" "$SID"
	got=$(sl)
	[ "$got" = " │ foo" ]
}

@test "two active toggles, locale-stable order" {
	write_toggle alpha session
	write_toggle bravo session
	. "$(repo_root)/lib/toggle.sh"
	toggle_on session alpha "" "$SID"
	toggle_on session bravo "" "$SID"
	got=$(sl)
	[ "$got" = " │ alpha │ bravo" ]
}

@test "custom toggle_<name>_statusline replaces the default name" {
	write_toggle devlog session 'toggle_devlog_statusline() { printf "devlog (3)"; }'
	. "$(repo_root)/lib/toggle.sh"
	toggle_on session devlog "" "$SID"
	got=$(sl)
	[ "$got" = " │ devlog (3)" ]
}

@test "TOGGLE_STATUSLINE=0 suppresses the fragment" {
	write_toggle hidden session "TOGGLE_STATUSLINE=0"
	. "$(repo_root)/lib/toggle.sh"
	toggle_on session hidden "" "$SID"
	got=$(sl)
	[ -z "$got" ]
}

@test "scope-unavailable toggle is silently omitted" {
	write_toggle proj project
	. "$(repo_root)/lib/toggle.sh"
	# Activate it for THIS cwd.
	toggle_on project proj "$CWD" ""
	# Then ask the statusline with NO cwd → scope unavailable.
	got=$(sl "")
	[ -z "$got" ]
}

@test "two custom statusline fns do not collide between subshells" {
	write_toggle aaa session 'toggle_aaa_statusline() { printf "A1"; }'
	write_toggle bbb session 'toggle_bbb_statusline() { printf "B1"; }'
	. "$(repo_root)/lib/toggle.sh"
	toggle_on session aaa "" "$SID"
	toggle_on session bbb "" "$SID"
	got=$(sl)
	[ "$got" = " │ A1 │ B1" ]
}
