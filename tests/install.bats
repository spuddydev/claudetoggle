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

@test "settings_with_lock falls back to mkdir when flock is unavailable" {
	# Sanity: both code paths exist.
	grep -q 'command -v flock' "$REPO/scripts/settings_merge.sh"
	grep -q 'mkdir "$lockdir"' "$REPO/scripts/settings_merge.sh"

	# Drive the fallback by sourcing the helper with a flock that always
	# reports missing. The lock is exercised via a real settings.json edit.
	export CLAUDETOGGLE_HOME=$TMP/data
	mkdir -p "$CLAUDETOGGLE_HOME"
	printf '{}\n' >"$TMP/s.json"
	bash -c '
		set -eu
		# Stub: make `command -v flock` always fail in this shell.
		command() { if [ "$1" = "-v" ] && [ "$2" = "flock" ]; then return 1; fi; builtin command "$@"; }
		. "$1/scripts/settings_merge.sh"
		settings_with_lock settings_add_deny "$2" "Bash(touch /tmp/x)"
	' _ "$REPO" "$TMP/s.json"
	jq -e '.permissions.deny | any(. == "Bash(touch /tmp/x)")' "$TMP/s.json"
	# Lockdir must be cleaned up after the operation.
	[ ! -d "$CLAUDETOGGLE_HOME/settings.lock.d" ]
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

@test "setup.sh installs the create-claudetoggle skill and AUTHORING.md" {
	run_setup >/dev/null
	[ -L "$CLAUDE_HOME/skills/create-claudetoggle" ]
	target=$(readlink "$CLAUDE_HOME/skills/create-claudetoggle")
	[ "$target" = "$CLAUDETOGGLE_HOME/skills/create-claudetoggle" ]
	[ -f "$CLAUDETOGGLE_HOME/skills/create-claudetoggle/SKILL.md" ]
	[ -f "$CLAUDETOGGLE_HOME/docs/AUTHORING.md" ]
}

@test "uninstall removes the skill symlink when it points into our data home" {
	run_setup >/dev/null
	[ -L "$CLAUDE_HOME/skills/create-claudetoggle" ]
	"$PREFIX/bin/claudetoggle" uninstall >/dev/null
	[ ! -e "$CLAUDE_HOME/skills/create-claudetoggle" ]
}

@test "uninstall preserves an unrelated skill symlink at the same path" {
	run_setup >/dev/null
	# Replace our skill symlink with one that points elsewhere — uninstall
	# must not touch user-owned skill links.
	rm -f "$CLAUDE_HOME/skills/create-claudetoggle"
	mkdir -p "$TMP/elsewhere"
	ln -s "$TMP/elsewhere" "$CLAUDE_HOME/skills/create-claudetoggle"
	"$PREFIX/bin/claudetoggle" uninstall >/dev/null
	[ -L "$CLAUDE_HOME/skills/create-claudetoggle" ]
}

@test "claudetoggle add fails on missing TOGGLE_API" {
	run_setup >/dev/null
	src=$TMP/fixtures/no_api
	mkdir -p "$src"
	cat >"$src/toggle.sh" <<'EOF'
TOGGLE_NAME=no_api
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="x"
EOF
	run claudetoggle add "$src"
	[ "$status" -ne 0 ]
	[[ "$output" == *"TOGGLE_API"* ]]
}

@test "claudetoggle add rejects an unknown TOGGLE_API value" {
	run_setup >/dev/null
	src=$TMP/fixtures/api2
	mkdir -p "$src"
	cat >"$src/toggle.sh" <<'EOF'
TOGGLE_API=2
TOGGLE_NAME=api2
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="x"
EOF
	run claudetoggle add "$src"
	[ "$status" -ne 0 ]
	[[ "$output" == *"TOGGLE_API"* ]]
}

@test "claudetoggle: read_lines_into populates an array without mapfile" {
	# Regression: the CLI used `mapfile -t`, which is bash 4 only. macOS
	# still ships bash 3.2, so the call printed an error and silently left
	# the rules array empty — the toggle registered but its state directory
	# went unprotected. read_lines_into is the portable replacement.
	got=$(bash -c '
        . "$1/bin/claudetoggle" >/dev/null 2>&1 || true
        read_lines_into arr <<<"$(printf "a\nb\nc")"
        printf "%d|%s|%s|%s" "${#arr[@]}" "${arr[0]}" "${arr[1]}" "${arr[2]}"
    ' _ "$REPO")
	[ "$got" = "3|a|b|c" ]
}

@test "claudetoggle add wires deny rules end to end" {
	# Together with the read_lines_into unit case above, asserts that the
	# array populated by read_lines_into is consumed correctly by the
	# settings merge helper. A regression to mapfile would silently drop
	# the deny rules on macOS without breaking add itself.
	run_setup >/dev/null
	src=$(fixture_toggle deny_check session)
	run claudetoggle add "$src"
	[ "$status" -eq 0 ]
	jq -e '.permissions.deny | any(. == "Bash(touch *claudetoggle/state/deny_check/*)")' \
		"$CLAUDE_HOME/settings.json"
}
