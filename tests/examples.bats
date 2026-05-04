#!/usr/bin/env bats
# Validate every example toggle: parses, sources cleanly, declares all the
# required vars, and TOGGLE_NAME matches its directory.

load test_helper

examples_dir() {
	printf '%s\n' "$(repo_root)/examples"
}

@test "examples/coauth/toggle.sh parses with bash -n" {
	bash -n "$(examples_dir)/coauth/toggle.sh"
}

@test "examples/coauth/toggle.sh sources cleanly with all required vars" {
	got=$(bash -c '
        . "$1/coauth/toggle.sh"
        printf "%s|%s|%s|%s|%s|%s\n" \
            "${TOGGLE_API:-}" "${TOGGLE_NAME:-}" "${TOGGLE_SCOPE:-}" \
            "${TOGGLE_ON_MSG:+set}" "${TOGGLE_OFF_MSG:+set}" "${TOGGLE_MARKER:+set}"
    ' _ "$(examples_dir)")
	[ "$got" = "1|coauth|project|set|set|set" ]
}

@test "examples/coauth: TOGGLE_NAME matches dirname; <name>.md has marker" {
	. "$(examples_dir)/coauth/toggle.sh"
	[ "$TOGGLE_NAME" = "coauth" ]
	grep -q "$TOGGLE_MARKER" "$(examples_dir)/coauth/coauth.md"
}

@test "examples/devlog/toggle.sh parses and declares custom statusline fn" {
	bash -n "$(examples_dir)/devlog/toggle.sh"
	got=$(bash -c '
        . "$1/devlog/toggle.sh"
        if declare -F toggle_devlog_statusline >/dev/null; then printf "yes"; else printf "no"; fi
    ' _ "$(examples_dir)")
	[ "$got" = "yes" ]
}

@test "examples/devlog: silent toggle with marker present in markdown" {
	. "$(examples_dir)/devlog/toggle.sh"
	[ "$TOGGLE_NAME" = "devlog" ]
	[ "$TOGGLE_ANNOUNCE_ON_TOGGLE" = "0" ]
	grep -q "$TOGGLE_MARKER" "$(examples_dir)/devlog/devlog.md"
}

# Drive examples/coauth/commit-check.sh against fabricated PreToolUse JSON
# under both ON and OFF sentinel states. Catches the regression where
# scope_path's arity bug made the script always take the OFF branch.
coauth_check() {
	local cwd=$1 cmd=$2
	jq -nc --arg cwd "$cwd" --arg c "$cmd" \
		'{cwd:$cwd, tool_input:{command:$c}}' |
		bash "$(examples_dir)/coauth/commit-check.sh"
}

@test "examples/coauth/commit-check: OFF + no trailer → allow" {
	cwd=$BATS_TEST_TMPDIR/proj
	mkdir -p "$cwd"
	# Sentinel absent → OFF state.
	out=$(coauth_check "$cwd" 'git commit -m "feat: x"')
	[ -z "$out" ]
}

@test "examples/coauth/commit-check: OFF + trailer → deny" {
	cwd=$BATS_TEST_TMPDIR/proj
	mkdir -p "$cwd"
	cmd=$'git commit -m "feat: x\n\nCo-Authored-By: Claude <x@y>"'
	out=$(coauth_check "$cwd" "$cmd")
	got=$(jq -r .hookSpecificOutput.permissionDecisionReason <<<"$out")
	[[ "$got" == *"OFF but the commit message includes a Co-Authored-By trailer"* ]]
}

@test "examples/coauth/commit-check: ON + no trailer → deny" {
	cwd=$BATS_TEST_TMPDIR/proj
	mkdir -p "$cwd"
	. "$(repo_root)/lib/scope.sh"
	sentinel=$(scope_path project coauth "$cwd" "")
	mkdir -p "$(dirname "$sentinel")"
	: >"$sentinel"
	out=$(coauth_check "$cwd" 'git commit -m "feat: x"')
	got=$(jq -r .hookSpecificOutput.permissionDecisionReason <<<"$out")
	[[ "$got" == *"ON but the commit message lacks a Co-Authored-By"* ]]
}

@test "examples/coauth/commit-check: ON + trailer → allow" {
	cwd=$BATS_TEST_TMPDIR/proj
	mkdir -p "$cwd"
	. "$(repo_root)/lib/scope.sh"
	sentinel=$(scope_path project coauth "$cwd" "")
	mkdir -p "$(dirname "$sentinel")"
	: >"$sentinel"
	cmd=$'git commit -m "feat: x\n\nCo-Authored-By: Claude <x@y>"'
	out=$(coauth_check "$cwd" "$cmd")
	[ -z "$out" ]
}
