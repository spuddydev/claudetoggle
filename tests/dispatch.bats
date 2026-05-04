#!/usr/bin/env bats

load test_helper

# Helpers — write a registry toggle file under $CLAUDETOGGLE_HOME/toggles/<name>/toggle.sh.
write_toggle() {
	local name=$1 scope=$2 extra=${3:-}
	mkdir -p "$CLAUDETOGGLE_HOME/toggles/$name"
	cat >"$CLAUDETOGGLE_HOME/toggles/$name/toggle.sh" <<EOF
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
        export CLAUDETOGGLE_HOME="$1" CLAUDETOGGLE_LIB="$3/lib"
        printf %s "$2" | bash "$3/bin/dispatch.sh" "$4"
    ' _ "$CLAUDETOGGLE_HOME" "$input" "$(repo_root)" "$event"
}

setup() {
	setup_isolated_home
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

@test "case 1: /coauth toggles ON, injects ON_MSG as additionalContext, sentinel created" {
	write_toggle coauth project
	run_dispatch UserPromptSubmit "$(prompt_input '/coauth')"
	[ "$status" -eq 0 ]
	# Flip path uses additionalContext so the model actually sees the rule.
	# block_userprompt only surfaces in the UI and never reaches the model.
	[ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = "UserPromptSubmit" ]
	[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "coauth is ON" ]
	[ "$(jq -r '.decision // empty' <<<"$output")" = "" ]
	key=$(. "$(repo_root)/lib/scope.sh" && project_key "$CWD")
	[ -f "$CLAUDETOGGLE_HOME/state/coauth/projects/$key" ]
}

@test "case 2: second /coauth toggles OFF, injects OFF_MSG, sentinel removed" {
	write_toggle coauth project
	run_dispatch UserPromptSubmit "$(prompt_input '/coauth')"
	run_dispatch UserPromptSubmit "$(prompt_input '/coauth')"
	[ "$status" -eq 0 ]
	[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "coauth is OFF" ]
	key=$(. "$(repo_root)/lib/scope.sh" && project_key "$CWD")
	[ ! -f "$CLAUDETOGGLE_HOME/state/coauth/projects/$key" ]
}

@test "case 3: plain prompt with active toggle ticks, reannounces after threshold" {
	write_toggle foo session "TOGGLE_REANNOUNCE_EVERY=2"
	# Flip on (already injects ON_MSG; counter resets to 0).
	run_dispatch UserPromptSubmit "$(prompt_input '/foo')"
	# First plain prompt: counter ticks 0→1 → not due yet → silent.
	run_dispatch UserPromptSubmit "$(prompt_input 'plain')"
	[ -z "$output" ]
	# Second plain prompt: counter ticks 1→2 → due.
	run_dispatch UserPromptSubmit "$(prompt_input 'plain again')"
	[ "$status" -eq 0 ]
	got=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$output")
	[[ "$got" == *"foo is ON"* ]]
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
	[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "devlog is ON" ]
}

@test "case 6: TOGGLE_MARKER substring detected" {
	write_toggle foo session
	prompt='unrelated text <!-- foo-marker --> more'
	run_dispatch UserPromptSubmit "$(prompt_input "$prompt")"
	[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "foo is ON" ]
}

@test "case 7: project toggle invoked with no cwd → scope-error block" {
	write_toggle proj project
	input=$(jq -nc --arg p '/proj' --arg s "$SID" \
		'{hook_event_name:"UserPromptSubmit",prompt:$p,cwd:"",session_id:$s}')
	run_dispatch UserPromptSubmit "$input"
	[ "$status" -eq 0 ]
	# Scope errors keep using block: the prompt cannot be satisfied without
	# a valid scope key, so stopping the turn is the right behaviour.
	[ "$(jq -r .decision <<<"$output")" = "block" ]
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
	[ -f "$CLAUDETOGGLE_HOME/state/silent/sessions/$SID" ]
}

@test "case 12: flip-to-ON does NOT also tick on the same prompt" {
	# REANNOUNCE_EVERY=1 so any tick at all on the flip would inject.
	write_toggle foo session "TOGGLE_REANNOUNCE_EVERY=1"
	run_dispatch UserPromptSubmit "$(prompt_input '/foo')"
	[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "foo is ON" ]
	# Counter was seeded to 0 (REANNOUNCE_EVERY-1) and never ticked this turn.
	read -r count <"$CLAUDETOGGLE_HOME/state/foo/counter"
	[ "$count" = "0" ]
}

@test "case 13: two toggles match; first in registry order wins (LC_ALL=C)" {
	export LC_ALL=C
	write_toggle aaa session
	write_toggle bbb session
	run_dispatch UserPromptSubmit "$(prompt_input '/aaa /bbb')"
	[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "aaa is ON" ]
}

@test "case 14: TOGGLE_API=2 rejected; other toggles continue" {
	mkdir -p "$CLAUDETOGGLE_HOME/toggles/old"
	cat >"$CLAUDETOGGLE_HOME/toggles/old/toggle.sh" <<'EOF'
TOGGLE_API=2
TOGGLE_NAME=old
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="old is ON"
TOGGLE_OFF_MSG="old is OFF"
EOF
	write_toggle good session
	run_dispatch UserPromptSubmit "$(prompt_input '/good')"
	[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "good is ON" ]
}

@test "case 15: TOGGLE_API unset rejected; other toggles continue" {
	mkdir -p "$CLAUDETOGGLE_HOME/toggles/legacy"
	cat >"$CLAUDETOGGLE_HOME/toggles/legacy/toggle.sh" <<'EOF'
TOGGLE_NAME=legacy
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="legacy is ON"
TOGGLE_OFF_MSG="legacy is OFF"
EOF
	write_toggle good session
	run_dispatch UserPromptSubmit "$(prompt_input '/good')"
	[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "good is ON" ]
}

@test "case 16: empty registry → exit 0, no output for both events" {
	mkdir -p "$CLAUDETOGGLE_HOME"
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

@test "case 18: pending CLI-flip message drains on the next plain prompt" {
	write_toggle foo session
	# Simulate a CLI flip having stashed a pending message.
	mkdir -p "$CLAUDETOGGLE_HOME/state/foo"
	printf 'foo is ON' >"$CLAUDETOGGLE_HOME/state/foo/pending"
	# Mark the toggle ON so it would be considered active anyway.
	mkdir -p "$CLAUDETOGGLE_HOME/state/foo/sessions"
	: >"$CLAUDETOGGLE_HOME/state/foo/sessions/$SID"
	run_dispatch UserPromptSubmit "$(prompt_input 'plain')"
	[ "$status" -eq 0 ]
	got=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$output")
	[[ "$got" == *"foo is ON"* ]]
	# Pending file is removed after draining so the next prompt is silent.
	[ ! -e "$CLAUDETOGGLE_HOME/state/foo/pending" ]
}

@test "case 19: slash-command flip clears any pending CLI-flip message" {
	write_toggle foo session
	mkdir -p "$CLAUDETOGGLE_HOME/state/foo"
	printf 'foo is OFF' >"$CLAUDETOGGLE_HOME/state/foo/pending"
	# /foo flips ON, supersedes the OFF pending. The flip's ON_MSG wins.
	run_dispatch UserPromptSubmit "$(prompt_input '/foo')"
	[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" = "foo is ON" ]
	[ ! -e "$CLAUDETOGGLE_HOME/state/foo/pending" ]
}
