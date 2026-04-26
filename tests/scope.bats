#!/usr/bin/env bats

load test_helper

setup() {
	setup_isolated_home
	load_lib scope
}

teardown() {
	teardown_isolated_home
}

@test "project_key is deterministic for the same input" {
	a=$(project_key /tmp)
	b=$(project_key /tmp)
	[ "$a" = "$b" ]
}

@test "project_key differs for different paths" {
	a=$(project_key /tmp)
	b=$(project_key /var)
	[ "$a" != "$b" ]
}

@test "project_key is 16 hex chars" {
	k=$(project_key /tmp)
	[ "${#k}" -eq 16 ]
	[[ "$k" =~ ^[0-9a-f]{16}$ ]]
}

@test "scope_path global ignores cwd and session" {
	got=$(scope_path global feat "" "")
	[ "$got" = "$CLAUDETOGGLE_HOME/state/feat/global" ]
}

@test "scope_path global appends parts" {
	got=$(scope_path global feat "" "" sub file)
	[ "$got" = "$CLAUDETOGGLE_HOME/state/feat/global/sub/file" ]
}

@test "scope_path project requires cwd" {
	run scope_path project feat "" ""
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "scope_path project hashes cwd" {
	got=$(scope_path project feat /tmp "")
	key=$(project_key /tmp)
	[ "$got" = "$CLAUDETOGGLE_HOME/state/feat/projects/$key" ]
}

@test "scope_path session requires session id" {
	run scope_path session feat /tmp ""
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "scope_path session uses raw session id" {
	got=$(scope_path session feat "" abc123)
	[ "$got" = "$CLAUDETOGGLE_HOME/state/feat/sessions/abc123" ]
}

@test "scope_path rejects unknown scope" {
	run scope_path bogus feat "" ""
	[ "$status" -eq 1 ]
}
