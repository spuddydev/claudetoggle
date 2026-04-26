#!/usr/bin/env bats
# Tests for setup.sh + the per-toggle wiring done via `claudetoggle add`.

load test_helper

setup() {
	export TMP=$(mktemp -d)
	export HOME=$TMP
	export CLAUDE_HOME=$TMP/.claude
	export CLAUDETOGGLE_HOME=$TMP/data/claudetoggle
	export PREFIX=$TMP/.local
	export REPO=$(repo_root)
	mkdir -p "$CLAUDE_HOME"
}

teardown() {
	[ -n "$TMP" ] && rm -rf "$TMP"
}

# Drop a fixture toggle on disk (NOT inside the registry yet — `add` will copy).
fixture_toggle() {
	local name=$1 scope=${2:-session} extra=${3:-}
	local d=$TMP/fixtures/$name
	mkdir -p "$d"
	cat >"$d/toggle.sh" <<EOF
TOGGLE_API=1
TOGGLE_NAME=$name
TOGGLE_SCOPE=$scope
TOGGLE_ON_MSG="$name on"
TOGGLE_OFF_MSG="$name off"
$extra
EOF
	cat >"$d/$name.md" <<EOF
---
description: Toggle $name
---
<!-- $name-marker -->
EOF
	printf '%s\n' "$d"
}

run_setup() {
	bash "$REPO/setup.sh" --local="$REPO" "$@"
}

claudetoggle() {
	"$PREFIX/bin/claudetoggle" "$@"
}

@test "setup.sh places framework files and the CLI on PATH" {
	run run_setup
	[ "$status" -eq 0 ]
	[ -f "$CLAUDETOGGLE_HOME/lib/scope.sh" ]
	[ -f "$CLAUDETOGGLE_HOME/bin/dispatch.sh" ]
	[ -f "$CLAUDETOGGLE_HOME/bin/statusline.sh" ]
	[ -f "$CLAUDETOGGLE_HOME/bin/claudetoggle" ]
	[ -x "$PREFIX/bin/claudetoggle" ]
}

@test "setup.sh wires the dispatcher into settings.json (idempotent)" {
	run_setup >/dev/null
	jq -e '.hooks.UserPromptSubmit[0].hooks[0].command | contains("claudetoggle:dispatch")' "$CLAUDE_HOME/settings.json"
	jq -e '.hooks.SessionStart[0].hooks[0].command | contains("claudetoggle:dispatch")' "$CLAUDE_HOME/settings.json"
	cp "$CLAUDE_HOME/settings.json" "$TMP/first"
	run_setup >/dev/null
	diff "$TMP/first" "$CLAUDE_HOME/settings.json"
}

@test "setup.sh refuses malformed settings.json" {
	printf 'not json{{{' >"$CLAUDE_HOME/settings.json"
	run run_setup
	[ "$status" -ne 0 ]
	[[ "$output" == *"not valid JSON"* ]]
}

@test "setup.sh preserves user-added unrelated hooks" {
	cat >"$CLAUDE_HOME/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {"matcher":"Bash","hooks":[{"type":"command","command":"bash /user/script.sh","timeout":5}]}
    ]
  }
}
EOF
	run_setup >/dev/null
	jq -e '.hooks.PreToolUse[0].hooks[0].command == "bash /user/script.sh"' "$CLAUDE_HOME/settings.json"
}

@test "setup.sh leaves statusLine.command unchanged" {
	cat >"$CLAUDE_HOME/settings.json" <<'EOF'
{ "statusLine": { "type": "command", "command": "bash \"$HOME/my-statusline.sh\"" } }
EOF
	run_setup >/dev/null
	got=$(jq -r '.statusLine.command' "$CLAUDE_HOME/settings.json")
	[ "$got" = 'bash "$HOME/my-statusline.sh"' ]
}

@test "claudetoggle add copies a fixture and wires it (markdown, deny, settings)" {
	run_setup >/dev/null
	src=$(fixture_toggle foo session)
	run claudetoggle add "$src"
	[ "$status" -eq 0 ]
	[ -d "$CLAUDETOGGLE_HOME/toggles/foo" ]
	[ -L "$CLAUDE_HOME/commands/foo.md" ]
	jq -e '.permissions.deny | any(. == "Bash(touch *claudetoggle/state/foo/*)")' "$CLAUDE_HOME/settings.json"
	jq -e '.permissions.deny | any(. == "Bash(* >> *claudetoggle/state/foo/*)")' "$CLAUDE_HOME/settings.json"
}

@test "claudetoggle add fails on TOGGLE_NAME mismatch with the directory name" {
	run_setup >/dev/null
	src=$TMP/fixtures/bad
	mkdir -p "$src"
	cat >"$src/toggle.sh" <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=different
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="x"
EOF
	run claudetoggle add "$src"
	[ "$status" -ne 0 ]
}

@test "claudetoggle add of a TOGGLE_EXTRA_HOOKS toggle registers the peer hook" {
	run_setup >/dev/null
	src=$TMP/fixtures/bar
	mkdir -p "$src"
	cat >"$src/toggle.sh" <<EOF
TOGGLE_API=1
TOGGLE_NAME=bar
TOGGLE_SCOPE=project
TOGGLE_ON_MSG="bar on"
TOGGLE_OFF_MSG="bar off"
TOGGLE_EXTRA_HOOKS=()
TOGGLE_EXTRA_HOOKS+=("PreToolUse"\$'\x1f'"Bash"\$'\x1f'"Bash(git commit *)"\$'\x1f'"check.sh")
EOF
	cat >"$src/bar.md" <<'EOF'
---
description: bar
---
EOF
	: >"$src/check.sh"
	run claudetoggle add "$src"
	[ "$status" -eq 0 ]
	got=$(jq -r '.hooks.PreToolUse[0].matcher' "$CLAUDE_HOME/settings.json")
	[ "$got" = "Bash" ]
	got=$(jq -r '.hooks.PreToolUse[0].hooks[0].if' "$CLAUDE_HOME/settings.json")
	[ "$got" = "Bash(git commit *)" ]
	jq -e '.hooks.PreToolUse[0].hooks[0].command | contains("claudetoggle:bar:0")' "$CLAUDE_HOME/settings.json"
}

@test "claudetoggle add of a missing markdown skips the symlink without erroring" {
	run_setup >/dev/null
	src=$TMP/fixtures/baz
	mkdir -p "$src"
	cat >"$src/toggle.sh" <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=baz
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="baz on"
TOGGLE_OFF_MSG="baz off"
EOF
	run claudetoggle add "$src"
	[ "$status" -eq 0 ]
	[ ! -e "$CLAUDE_HOME/commands/baz.md" ]
}

@test "claudetoggle add of a shipped example by short name copies from examples/" {
	run_setup >/dev/null
	[ -d "$CLAUDETOGGLE_HOME/examples/coauth" ]
	run claudetoggle add coauth
	[ "$status" -eq 0 ]
	[ -d "$CLAUDETOGGLE_HOME/toggles/coauth" ]
	[ -L "$CLAUDE_HOME/commands/coauth.md" ]
}

@test "claudetoggle add --dry-run reports actions without writing" {
	run_setup >/dev/null
	src=$(fixture_toggle foo session)
	cp "$CLAUDE_HOME/settings.json" "$TMP/before"
	run claudetoggle add --dry-run "$src"
	[ "$status" -eq 0 ]
	[[ "$output" == *"--dry-run foo"* ]]
	[[ "$output" == *"deny rules"* ]]
	[[ "$output" == *"No files written"* ]]
	[ ! -d "$CLAUDETOGGLE_HOME/toggles/foo" ]
	[ ! -L "$CLAUDE_HOME/commands/foo.md" ]
	diff "$TMP/before" "$CLAUDE_HOME/settings.json"
}

@test "claudetoggle add --dry-run still validates metadata" {
	run_setup >/dev/null
	src=$TMP/fixtures/bad
	mkdir -p "$src"
	cat >"$src/toggle.sh" <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=different
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="x"
EOF
	run claudetoggle add --dry-run "$src"
	[ "$status" -ne 0 ]
}

@test "claudetoggle add fails on missing TOGGLE_SCOPE" {
	run_setup >/dev/null
	src=$TMP/fixtures/no_scope
	mkdir -p "$src"
	cat >"$src/toggle.sh" <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=no_scope
TOGGLE_ON_MSG="x"
EOF
	run claudetoggle add "$src"
	[ "$status" -ne 0 ]
	[[ "$output" == *"TOGGLE_SCOPE"* ]]
}

@test "claudetoggle add fails on invalid TOGGLE_SCOPE" {
	run_setup >/dev/null
	src=$TMP/fixtures/bad_scope
	mkdir -p "$src"
	cat >"$src/toggle.sh" <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=bad_scope
TOGGLE_SCOPE=universe
TOGGLE_ON_MSG="x"
EOF
	run claudetoggle add "$src"
	[ "$status" -ne 0 ]
	[[ "$output" == *"global, project or session"* ]]
}

@test "claudetoggle remove --dry-run reports actions without removing" {
	run_setup >/dev/null
	src=$(fixture_toggle foo session)
	claudetoggle add "$src" >/dev/null
	cp "$CLAUDE_HOME/settings.json" "$TMP/before"
	run claudetoggle remove --dry-run foo
	[ "$status" -eq 0 ]
	[[ "$output" == *"--dry-run foo"* ]]
	[[ "$output" == *"No files written"* ]]
	[ -d "$CLAUDETOGGLE_HOME/toggles/foo" ]
	[ -L "$CLAUDE_HOME/commands/foo.md" ]
	diff "$TMP/before" "$CLAUDE_HOME/settings.json"
}

@test "claudetoggle version prints the recorded VERSION" {
	run_setup --version=v9.9.9 >/dev/null
	run claudetoggle version
	[ "$status" -eq 0 ]
	[ "$output" = "claudetoggle v9.9.9" ]
	run claudetoggle --version
	[ "$status" -eq 0 ]
	[ "$output" = "claudetoggle v9.9.9" ]
}

@test "claudetoggle list flags a stale slash-command symlink" {
	run_setup >/dev/null
	src=$(fixture_toggle foo session)
	claudetoggle add "$src" >/dev/null
	# Break the symlink target so the link dangles.
	rm -f "$CLAUDETOGGLE_HOME/toggles/foo/foo.md"
	run claudetoggle list
	[ "$status" -eq 0 ]
	[[ "$output" == *"WARN: stale slash-command symlink"* ]]
}
