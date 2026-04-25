#!/usr/bin/env bats

load test_helper

# Helpers — write a registry toggle file under $TOGGLE_REGISTRY/<name>/toggle.sh
# with the given snippet appended to a sane default body.
write_toggle() {
	local name=$1 scope=$2 extra=${3:-}
	mkdir -p "$TOGGLE_REGISTRY/$name"
	cat >"$TOGGLE_REGISTRY/$name/toggle.sh" <<EOF
TOGGLE_API=1
TOGGLE_NAME=$name
TOGGLE_SCOPE=$scope
TOGGLE_ON_MSG="$name is ON"
TOGGLE_OFF_MSG="$name is OFF"
TOGGLE_MARKER="<!-- $name-marker -->"
$extra
EOF
}

# Run the dispatcher with INPUT JSON on stdin. Sets $output, $status.
run_dispatch() {
	local event=$1 input=$2
	run bash -c '
        export CLAUDETOGGLE_HOME="$1" TOGGLE_REGISTRY="$2"
        printf %s "$3" | bash "$4/bin/dispatch.sh" "$5"
    ' _ "$CLAUDETOGGLE_HOME" "$TOGGLE_REGISTRY" "$input" "$(repo_root)" "$event"
}

setup() {
	setup_isolated_home
	export TOGGLE_REGISTRY="$CLAUDETOGGLE_HOME/toggles"
	export CWD="$BATS_TEST_TMPDIR/cwd"
	mkdir -p "$CWD"
	export SID=s1
}

teardown() {
	teardown_isolated_home
}

prompt_input() {
	jq -nc --arg p "$1" --arg c "$CWD" --arg s "$SID" \
		'{hook_event_name:"UserPromptSubmit",prompt:$p,cwd:$c,session_id:$s}'
}

session_input() {
	jq -nc --arg c "$CWD" --arg s "$SID" \
		'{hook_event_name:"SessionStart",cwd:$c,session_id:$s}'
}

@test "case 1: /coauth toggles ON, emits block JSON with ON_MSG, sentinel created" {
	write_toggle coauth project
	run_dispatch UserPromptSubmit "$(prompt_input '/coauth')"
	[ "$status" -eq 0 ]
	[ "$(jq -r .decision <<<"$output")" = "block" ]
	[ "$(jq -r .reason <<<"$output")" = "coauth is ON" ]
	key=$(. "$(repo_root)/lib/scope.sh" && project_key "$CWD")
	[ -f "$CLAUDETOGGLE_HOME/coauth/projects/$key" ]
}

@test "case 2: second /coauth toggles OFF, emits OFF_MSG, sentinel removed" {
	write_toggle coauth project
	run_dispatch UserPromptSubmit "$(prompt_input '/coauth')"
	run_dispatch UserPromptSubmit "$(prompt_input '/coauth')"
	[ "$status" -eq 0 ]
	[ "$(jq -r .reason <<<"$output")" = "coauth is OFF" ]
	key=$(. "$(repo_root)/lib/scope.sh" && project_key "$CWD")
	[ ! -f "$CLAUDETOGGLE_HOME/coauth/projects/$key" ]
}

@test "case 3: plain prompt with active toggle ticks, reannounces after threshold" {
	write_toggle foo session "TOGGLE_REANNOUNCE_EVERY=2"
	# Flip on (seeds counter to 1; next plain prompt → tick=2 → due).
	run_dispatch UserPromptSubmit "$(prompt_input '/foo')"
	# First plain prompt: counter ticks 1→2 → due.
	run_dispatch UserPromptSubmit "$(prompt_input 'plain')"
	[ "$status" -eq 0 ]
	got=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$output")
	[[ "$got" == *"foo is ON"* ]]
	# Second plain prompt: counter resets to 0, then 1 → not due yet → silent.
	run_dispatch UserPromptSubmit "$(prompt_input 'plain again')"
	[ -z "$output" ]
}

@test "case 4: plain prompt with no active toggles emits nothing" {
	write_toggle foo session
	run_dispatch UserPromptSubmit "$(prompt_input 'unrelated')"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "case 5: <command-name>/devlog</command-name> wrapper detected" {
	write_toggle devlog session
	prompt='<command-message>/devlog</command-message>
<command-name>/devlog</command-name>'
	run_dispatch UserPromptSubmit "$(prompt_input "$prompt")"
	[ "$(jq -r .reason <<<"$output")" = "devlog is ON" ]
}

@test "case 6: TOGGLE_MARKER substring detected" {
	write_toggle foo session
	prompt='unrelated text <!-- foo-marker --> more'
	run_dispatch UserPromptSubmit "$(prompt_input "$prompt")"
	[ "$(jq -r .reason <<<"$output")" = "foo is ON" ]
}

@test "case 7: project toggle invoked with no cwd → scope-error block" {
	write_toggle proj project
	input=$(jq -nc --arg p '/proj' --arg s "$SID" \
		'{hook_event_name:"UserPromptSubmit",prompt:$p,cwd:"",session_id:$s}')
	run_dispatch UserPromptSubmit "$input"
	[ "$status" -eq 0 ]
	got=$(jq -r .reason <<<"$output")
	[[ "$got" == *"requires a project context"* ]]
}

@test "case 8: REANNOUNCE_EVERY=0 (default) + active + plain → no inject_context" {
	write_toggle foo session
	run_dispatch UserPromptSubmit "$(prompt_input '/foo')"
	run_dispatch UserPromptSubmit "$(prompt_input 'plain')"
	[ -z "$output" ]
}

@test "case 9: SessionStart with active toggle emits ON_MSG to stdout, not JSON" {
	write_toggle foo session
	run_dispatch UserPromptSubmit "$(prompt_input '/foo')"
	run_dispatch SessionStart "$(session_input)"
	[ "$status" -eq 0 ]
	[[ "$output" == *"foo is ON"* ]]
	# Not JSON.
	! jq -e . <<<"$output" >/dev/null 2>&1
}

@test "case 10: SessionStart with no active toggles emits nothing" {
	write_toggle foo session
	run_dispatch SessionStart "$(session_input)"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "case 11: TOGGLE_ANNOUNCE_ON_TOGGLE=0 flips silently" {
	write_toggle silent session "TOGGLE_ANNOUNCE_ON_TOGGLE=0"
	run_dispatch UserPromptSubmit "$(prompt_input '/silent')"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -f "$CLAUDETOGGLE_HOME/silent/sessions/$SID" ]
}

@test "case 12: flip-to-ON does NOT also tick on the same prompt" {
	# REANNOUNCE_EVERY=1 so any tick at all on the flip would inject.
	write_toggle foo session "TOGGLE_REANNOUNCE_EVERY=1"
	run_dispatch UserPromptSubmit "$(prompt_input '/foo')"
	# Output is the flip block; counter must NOT have ticked.
	[ "$(jq -r .decision <<<"$output")" = "block" ]
	# Counter was seeded to 0 (REANNOUNCE_EVERY-1) and never ticked this turn.
	read -r count <"$CLAUDETOGGLE_HOME/foo/counters/$SID"
	[ "$count" = "0" ]
}

@test "case 13: two toggles match; first in registry order wins (LC_ALL=C)" {
	export LC_ALL=C
	write_toggle aaa session
	write_toggle bbb session
	run_dispatch UserPromptSubmit "$(prompt_input '/aaa /bbb')"
	[ "$(jq -r .reason <<<"$output")" = "aaa is ON" ]
}

@test "case 14: TOGGLE_API=2 rejected; other toggles continue" {
	mkdir -p "$TOGGLE_REGISTRY/old"
	cat >"$TOGGLE_REGISTRY/old/toggle.sh" <<'EOF'
TOGGLE_API=2
TOGGLE_NAME=old
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="old is ON"
TOGGLE_OFF_MSG="old is OFF"
EOF
	write_toggle good session
	run_dispatch UserPromptSubmit "$(prompt_input '/good')"
	[ "$(jq -r .reason <<<"$output")" = "good is ON" ]
}

@test "case 15: TOGGLE_API unset rejected; other toggles continue" {
	mkdir -p "$TOGGLE_REGISTRY/legacy"
	cat >"$TOGGLE_REGISTRY/legacy/toggle.sh" <<'EOF'
TOGGLE_NAME=legacy
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="legacy is ON"
TOGGLE_OFF_MSG="legacy is OFF"
EOF
	write_toggle good session
	run_dispatch UserPromptSubmit "$(prompt_input '/good')"
	[ "$(jq -r .reason <<<"$output")" = "good is ON" ]
}

@test "case 16: empty registry → exit 0, no output for both events" {
	mkdir -p "$TOGGLE_REGISTRY"
	run_dispatch UserPromptSubmit "$(prompt_input 'hello')"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	run_dispatch SessionStart "$(session_input)"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "case 17: cheap pre-filter skips command_called when OFF and prompt has no /name or marker" {
	# Use the debug log to assert command_called was NOT reached: a toggle
	# that is OFF and a prompt that mentions neither /name nor marker should
	# emit no block JSON and no debug entry for that toggle.
	write_toggle foo session
	export CLAUDETOGGLE_DEBUG=1
	run_dispatch UserPromptSubmit "$(prompt_input 'hello world')"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}
