#!/usr/bin/env bats

load test_helper

setup() {
	setup_isolated_home
	load_lib hook_io
}

teardown() {
	teardown_isolated_home
}

@test "block_userprompt emits jq object with decision and reason and exits 0" {
	# Subshell so the helper's exit doesn't kill the test.
	run bash -c '. "$1/lib/hook_io.sh" && block_userprompt "stop right there"' _ "$(repo_root)"
	[ "$status" -eq 0 ]
	got=$(printf '%s' "$output" | jq -r '.decision + "|" + .reason')
	[ "$got" = "block|stop right there" ]
}

@test "inject_context emits hookSpecificOutput with additionalContext" {
	run bash -c '. "$1/lib/hook_io.sh" && inject_context "remember this"' _ "$(repo_root)"
	[ "$status" -eq 0 ]
	got=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName + "|" + .hookSpecificOutput.additionalContext')
	[ "$got" = "UserPromptSubmit|remember this" ]
}

@test "hook_log is a no-op when CLAUDETOGGLE_DEBUG is unset" {
	unset CLAUDETOGGLE_DEBUG
	hook_log "should not appear"
	[ ! -f "$CLAUDETOGGLE_HOME/hooks-debug.log" ]
}

@test "hook_log writes a line when CLAUDETOGGLE_DEBUG is set" {
	export CLAUDETOGGLE_DEBUG=1
	hook_log "marker line"
	[ -f "$CLAUDETOGGLE_HOME/hooks-debug.log" ]
	grep -q 'marker line' "$CLAUDETOGGLE_HOME/hooks-debug.log"
}

@test "deny_pretooluse emits PreToolUse deny JSON and exits 0" {
	run bash -c '. "$1/lib/hook_io.sh" && deny_pretooluse "no go"' _ "$(repo_root)"
	[ "$status" -eq 0 ]
	got=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName + "|" + .hookSpecificOutput.permissionDecision + "|" + .hookSpecificOutput.permissionDecisionReason')
	[ "$got" = "PreToolUse|deny|no go" ]
}

@test "deny_with_errors is a no-op when no errors are passed" {
	run bash -c '. "$1/lib/hook_io.sh" && deny_with_errors hdr cmd "git x"' _ "$(repo_root)"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "deny_with_errors emits a multi-line deny reason" {
	run bash -c '. "$1/lib/hook_io.sh" && deny_with_errors hdr cmd "git commit -m x" "header too long" "missing trailer"' _ "$(repo_root)"
	[ "$status" -eq 0 ]
	reason=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
	[[ "$reason" == "hdr rejected:"* ]]
	[[ "$reason" == *"header too long"* ]]
	[[ "$reason" == *"missing trailer"* ]]
	[[ "$reason" == *"cmd: git commit -m x"* ]]
}
