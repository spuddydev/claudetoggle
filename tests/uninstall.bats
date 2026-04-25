#!/usr/bin/env bats

load test_helper

setup() {
	export TMP=$(mktemp -d)
	export HOME=$TMP
	export CLAUDE_HOME=$TMP/.claude
	export CLAUDETOGGLE_HOME=$TMP/.claudetoggle
	export REPO=$(repo_root)
	mkdir -p "$CLAUDETOGGLE_HOME/toggles/foo"
	cat >"$CLAUDETOGGLE_HOME/toggles/foo/toggle.sh" <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=foo
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="foo on"
TOGGLE_OFF_MSG="foo off"
EOF
	cat >"$CLAUDETOGGLE_HOME/toggles/foo/foo.md" <<'EOF'
---
description: Toggle foo
---
EOF
	bash "$REPO/install.sh" >/dev/null
}

teardown() {
	[ -n "$TMP" ] && rm -rf "$TMP"
}

@test "removes only tagged hook entries" {
	jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"bash /user.sh","timeout":5}]}]' \
		"$CLAUDE_HOME/settings.json" >"$TMP/s2"
	mv "$TMP/s2" "$CLAUDE_HOME/settings.json"
	run bash "$REPO/uninstall.sh"
	[ "$status" -eq 0 ]
	jq -e '.hooks.PreToolUse[0].hooks[0].command == "bash /user.sh"' "$CLAUDE_HOME/settings.json"
	jq -e '.hooks.UserPromptSubmit // [] | length == 0' "$CLAUDE_HOME/settings.json"
}

@test "removes per-toggle deny rules" {
	bash "$REPO/uninstall.sh" >/dev/null
	got=$(jq -r '(.permissions.deny // []) | join("|")' "$CLAUDE_HOME/settings.json")
	[ "$got" = "" ]
}

@test "preserves $CLAUDETOGGLE_HOME/state by default" {
	mkdir -p "$CLAUDETOGGLE_HOME/state/foo/sessions"
	: >"$CLAUDETOGGLE_HOME/state/foo/sessions/sentinel"
	bash "$REPO/uninstall.sh" >/dev/null
	[ -f "$CLAUDETOGGLE_HOME/state/foo/sessions/sentinel" ]
}

@test "--purge removes the home directory" {
	bash "$REPO/uninstall.sh" --purge >/dev/null
	[ ! -d "$CLAUDETOGGLE_HOME" ]
}

@test "is idempotent" {
	bash "$REPO/uninstall.sh" >/dev/null
	cp "$CLAUDE_HOME/settings.json" "$TMP/once"
	bash "$REPO/uninstall.sh" >/dev/null
	diff "$TMP/once" "$CLAUDE_HOME/settings.json"
}

@test "missing settings.json is a no-op" {
	rm -f "$CLAUDE_HOME/settings.json"
	run bash "$REPO/uninstall.sh"
	[ "$status" -eq 0 ]
}

@test "empty event arrays are pruned" {
	bash "$REPO/uninstall.sh" >/dev/null
	# Neither UserPromptSubmit nor SessionStart should remain as keys.
	jq -e '.hooks.UserPromptSubmit == null' "$CLAUDE_HOME/settings.json"
	jq -e '.hooks.SessionStart == null' "$CLAUDE_HOME/settings.json"
}
