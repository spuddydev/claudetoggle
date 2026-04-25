#!/usr/bin/env bats

load test_helper

setup() {
	export TMP=$(mktemp -d)
	export HOME=$TMP
	export CLAUDE_HOME=$TMP/.claude
	export CLAUDETOGGLE_HOME=$TMP/.claudetoggle
	export REPO=$(repo_root)
	mkdir -p "$CLAUDETOGGLE_HOME/toggles"
}

teardown() {
	[ -n "$TMP" ] && rm -rf "$TMP"
}

# Drop a registry toggle into $CLAUDETOGGLE_HOME/toggles/<name>/.
register() {
	local name=$1 scope=${2:-session} extra=${3:-}
	mkdir -p "$CLAUDETOGGLE_HOME/toggles/$name"
	cat >"$CLAUDETOGGLE_HOME/toggles/$name/toggle.sh" <<EOF
TOGGLE_API=1
TOGGLE_NAME=$name
TOGGLE_SCOPE=$scope
TOGGLE_ON_MSG="$name on"
TOGGLE_OFF_MSG="$name off"
$extra
EOF
	cat >"$CLAUDETOGGLE_HOME/toggles/$name/$name.md" <<EOF
---
description: Toggle $name
---
<!-- $name-marker -->
EOF
}

@test "clean install on empty home" {
	register foo
	run bash "$REPO/install.sh"
	[ "$status" -eq 0 ]
	[ -L "$CLAUDETOGGLE_HOME/lib" ]
	[ -L "$CLAUDETOGGLE_HOME/bin" ]
	[ -L "$CLAUDE_HOME/commands/foo.md" ]
	jq -e '.hooks.UserPromptSubmit[0].hooks[0].command | contains("claudetoggle:dispatch")' "$CLAUDE_HOME/settings.json"
	jq -e '.permissions.deny | length == 10' "$CLAUDE_HOME/settings.json"
}

@test "second run is byte-identical (idempotent)" {
	register foo
	bash "$REPO/install.sh" >/dev/null
	cp "$CLAUDE_HOME/settings.json" "$TMP/first"
	bash "$REPO/install.sh" >/dev/null
	diff "$TMP/first" "$CLAUDE_HOME/settings.json"
}

@test "preserves user-added unrelated hooks" {
	register foo
	mkdir -p "$CLAUDE_HOME"
	cat >"$CLAUDE_HOME/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type":"command","command":"bash /user/script.sh","timeout":5}
        ]
      }
    ]
  }
}
EOF
	bash "$REPO/install.sh" >/dev/null
	jq -e '.hooks.PreToolUse[0].hooks[0].command == "bash /user/script.sh"' "$CLAUDE_HOME/settings.json"
}

@test "deny templates target the toggle's state subtree" {
	register foo
	bash "$REPO/install.sh" >/dev/null
	jq -e '.permissions.deny | any(. == "Bash(touch *.claudetoggle/state/foo/*)")' "$CLAUDE_HOME/settings.json"
	jq -e '.permissions.deny | any(. == "Bash(* >> *.claudetoggle/state/foo/*)")' "$CLAUDE_HOME/settings.json"
}

@test "refuses malformed settings.json" {
	register foo
	mkdir -p "$CLAUDE_HOME"
	printf 'not json{{{' >"$CLAUDE_HOME/settings.json"
	run bash "$REPO/install.sh"
	[ "$status" -eq 2 ]
	[[ "$output" == *"not valid JSON"* ]]
}

@test "missing <name>.md skipped without error" {
	register foo
	rm "$CLAUDETOGGLE_HOME/toggles/foo/foo.md"
	run bash "$REPO/install.sh"
	[ "$status" -eq 0 ]
	[ ! -e "$CLAUDE_HOME/commands/foo.md" ]
}

@test "TOGGLE_NAME mismatch aborts that toggle with file path; others continue" {
	register foo
	mkdir -p "$CLAUDETOGGLE_HOME/toggles/bad"
	cat >"$CLAUDETOGGLE_HOME/toggles/bad/toggle.sh" <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=different
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="x"
EOF
	run bash "$REPO/install.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"toggles/bad/toggle.sh"* ]]
	[[ "$output" == *"expected bad"* ]]
	jq -e '.permissions.deny | any(. == "Bash(touch *.claudetoggle/state/foo/*)")' "$CLAUDE_HOME/settings.json"
	jq -e '.permissions.deny | any(. == "Bash(touch *.claudetoggle/state/bad/*)") | not' "$CLAUDE_HOME/settings.json"
}

@test "statusLine.command is unchanged after install" {
	register foo
	mkdir -p "$CLAUDE_HOME"
	cat >"$CLAUDE_HOME/settings.json" <<'EOF'
{ "statusLine": { "type": "command", "command": "bash \"$HOME/my-statusline.sh\"" } }
EOF
	cp "$CLAUDE_HOME/settings.json" "$TMP/before"
	bash "$REPO/install.sh" >/dev/null
	got=$(jq -r '.statusLine.command' "$CLAUDE_HOME/settings.json")
	[ "$got" = 'bash "$HOME/my-statusline.sh"' ]
}

@test "TOGGLE_EXTRA_HOOKS entry is registered with sentinel" {
	mkdir -p "$CLAUDETOGGLE_HOME/toggles/bar"
	cat >"$CLAUDETOGGLE_HOME/toggles/bar/toggle.sh" <<EOF
TOGGLE_API=1
TOGGLE_NAME=bar
TOGGLE_SCOPE=project
TOGGLE_ON_MSG="bar on"
TOGGLE_OFF_MSG="bar off"
TOGGLE_EXTRA_HOOKS=()
TOGGLE_EXTRA_HOOKS+=("PreToolUse"\$'\x1f'"Bash"\$'\x1f'"Bash(git commit *)"\$'\x1f'"check.sh")
EOF
	: >"$CLAUDETOGGLE_HOME/toggles/bar/check.sh"
	bash "$REPO/install.sh" >/dev/null
	got=$(jq -r '.hooks.PreToolUse[0].matcher' "$CLAUDE_HOME/settings.json")
	[ "$got" = "Bash" ]
	got=$(jq -r '.hooks.PreToolUse[0].hooks[0].if' "$CLAUDE_HOME/settings.json")
	[ "$got" = "Bash(git commit *)" ]
	jq -e '.hooks.PreToolUse[0].hooks[0].command | contains("claudetoggle:bar:0")' "$CLAUDE_HOME/settings.json"
}

@test "concurrent install with sleep hook produces exactly one dispatcher entry" {
	register foo
	CLAUDETOGGLE_INSTALL_SLEEP=0.5 bash "$REPO/install.sh" >/dev/null &
	pid=$!
	sleep 0.1
	bash "$REPO/install.sh" >/dev/null
	wait "$pid"
	count=$(jq '[.hooks.UserPromptSubmit[0].hooks[] | select(.command | contains("claudetoggle:dispatch"))] | length' "$CLAUDE_HOME/settings.json")
	[ "$count" -eq 1 ]
}
