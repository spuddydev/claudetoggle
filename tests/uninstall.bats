#!/usr/bin/env bats
# Tests for `claudetoggle uninstall` (full teardown) and `claudetoggle remove`
# (per-toggle teardown).

load test_helper

setup() {
	export TMP=$(mktemp -d)
	export HOME=$TMP
	export CLAUDE_HOME=$TMP/.claude
	export CLAUDETOGGLE_HOME=$TMP/data/claudetoggle
	export PREFIX=$TMP/.local
	export REPO=$(repo_root)

	bash "$REPO/setup.sh" --local="$REPO" >/dev/null

	# Add the shipped coauth example so we have something to tear down.
	"$PREFIX/bin/claudetoggle" add coauth >/dev/null
}

teardown() {
	[ -n "$TMP" ] && rm -rf "$TMP"
}

ct() {
	"$PREFIX/bin/claudetoggle" "$@"
}

@test "uninstall removes only tagged hook entries" {
	jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"bash /user.sh","timeout":5}]}]' \
		"$CLAUDE_HOME/settings.json" >"$TMP/s2"
	mv "$TMP/s2" "$CLAUDE_HOME/settings.json"
	run ct uninstall
	[ "$status" -eq 0 ]
	jq -e '.hooks.PreToolUse[0].hooks[0].command == "bash /user.sh"' "$CLAUDE_HOME/settings.json"
	jq -e '.hooks.UserPromptSubmit // [] | length == 0' "$CLAUDE_HOME/settings.json"
}

@test "uninstall removes per-toggle deny rules" {
	ct uninstall >/dev/null
	got=$(jq -r '(.permissions.deny // []) | join("|")' "$CLAUDE_HOME/settings.json")
	[ "$got" = "" ]
}

@test "uninstall preserves data and state by default" {
	mkdir -p "$CLAUDETOGGLE_HOME/state/coauth/projects"
	: >"$CLAUDETOGGLE_HOME/state/coauth/projects/x"
	ct uninstall >/dev/null
	[ -f "$CLAUDETOGGLE_HOME/state/coauth/projects/x" ]
	[ -d "$CLAUDETOGGLE_HOME/toggles/coauth" ]
}

@test "uninstall --purge removes the data home" {
	ct uninstall --purge >/dev/null
	[ ! -d "$CLAUDETOGGLE_HOME" ]
}

@test "uninstall is idempotent" {
	ct uninstall >/dev/null
	cp "$CLAUDE_HOME/settings.json" "$TMP/once"
	ct uninstall >/dev/null
	diff "$TMP/once" "$CLAUDE_HOME/settings.json"
}

@test "uninstall prunes empty event arrays" {
	ct uninstall >/dev/null
	jq -e '.hooks.UserPromptSubmit == null' "$CLAUDE_HOME/settings.json"
	jq -e '.hooks.SessionStart == null' "$CLAUDE_HOME/settings.json"
}

@test "remove unwires only the named toggle" {
	ct add devlog >/dev/null
	ct remove coauth >/dev/null
	[ ! -d "$CLAUDETOGGLE_HOME/toggles/coauth" ]
	[ -d "$CLAUDETOGGLE_HOME/toggles/devlog" ]
	# coauth deny rule gone, devlog still there
	jq -e '.permissions.deny | any(. == "Bash(touch *claudetoggle/state/coauth/*)") | not' "$CLAUDE_HOME/settings.json"
	jq -e '.permissions.deny | any(. == "Bash(touch *claudetoggle/state/devlog/*)")' "$CLAUDE_HOME/settings.json"
}

@test "remove --keep-state preserves state directory" {
	mkdir -p "$CLAUDETOGGLE_HOME/state/coauth"
	: >"$CLAUDETOGGLE_HOME/state/coauth/marker"
	ct remove coauth --keep-state >/dev/null
	[ -f "$CLAUDETOGGLE_HOME/state/coauth/marker" ]
}

@test "uninstall.sh wrapper forwards to claudetoggle uninstall" {
	# Wrapper relies on $PATH first, then $PREFIX/bin, then $CLAUDETOGGLE_HOME/bin.
	run env PATH="$PREFIX/bin:$PATH" bash "$REPO/uninstall.sh"
	[ "$status" -eq 0 ]
}
