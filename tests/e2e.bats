#!/usr/bin/env bats
# End-to-end: setup.sh → claudetoggle add → drive the dispatcher → render the
# statusline → uninstall. Validates the pieces integrate.

load test_helper

setup() {
	export TMP=$(mktemp -d)
	export HOME=$TMP
	export CLAUDE_HOME=$TMP/.claude
	export CLAUDETOGGLE_HOME=$TMP/data/claudetoggle
	export PREFIX=$TMP/.local
	export REPO=$(repo_root)
	export CWD=$TMP/work
	export SID=e2e-1
	mkdir -p "$CWD"

	bash "$REPO/setup.sh" --local="$REPO" >/dev/null
	"$PREFIX/bin/claudetoggle" add coauth >/dev/null
	"$PREFIX/bin/claudetoggle" add devlog >/dev/null
}

teardown() {
	[ -n "$TMP" ] && rm -rf "$TMP"
}

dispatch() {
	local event=$1 input=$2
	printf %s "$input" | bash "$CLAUDETOGGLE_HOME/bin/dispatch.sh" "$event"
}

ct() {
	"$PREFIX/bin/claudetoggle" "$@"
}

p() {
	jq -nc --arg p "$1" --arg c "$CWD" --arg s "$SID" \
		'{hook_event_name:"UserPromptSubmit",prompt:$p,cwd:$c,session_id:$s}'
}

s() {
	jq -nc --arg c "$CWD" --arg s "$SID" \
		'{hook_event_name:"SessionStart",cwd:$c,session_id:$s}'
}

@test "setup placed lib, bin, examples, and the CLI on PATH" {
	[ -f "$CLAUDETOGGLE_HOME/lib/scope.sh" ]
	[ -f "$CLAUDETOGGLE_HOME/bin/dispatch.sh" ]
	[ -f "$CLAUDETOGGLE_HOME/bin/statusline.sh" ]
	[ -f "$CLAUDETOGGLE_HOME/bin/claudetoggle" ]
	[ -d "$CLAUDETOGGLE_HOME/examples/coauth" ]
	[ -x "$PREFIX/bin/claudetoggle" ]
}

@test "add registered slash-command symlinks and deny rules for both toggles" {
	[ -L "$CLAUDE_HOME/commands/coauth.md" ]
	[ -L "$CLAUDE_HOME/commands/devlog.md" ]
	jq -e '.permissions.deny | any(. == "Bash(touch *claudetoggle/state/coauth/*)")' "$CLAUDE_HOME/settings.json"
	jq -e '.permissions.deny | any(. == "Bash(touch *claudetoggle/state/devlog/*)")' "$CLAUDE_HOME/settings.json"
}

@test "/coauth flips ON, sentinel created, block reason matches ON_MSG" {
	out=$(dispatch UserPromptSubmit "$(p '/coauth')")
	got=$(jq -r .reason <<<"$out")
	[[ "$got" == *"coauth is ON"* ]]
	key=$(. "$REPO/lib/scope.sh" && project_key "$CWD")
	[ -f "$CLAUDETOGGLE_HOME/state/coauth/projects/$key" ]
}

@test "SessionStart after flip-on emits ON_MSG to stdout (not JSON)" {
	dispatch UserPromptSubmit "$(p '/coauth')" >/dev/null
	out=$(dispatch SessionStart "$(s)")
	[[ "$out" == *"coauth is ON"* ]]
	! jq -e . <<<"$out" >/dev/null 2>&1
}

@test "/devlog flips silently and statusline renders custom indicator" {
	out=$(dispatch UserPromptSubmit "$(p '/devlog')")
	[ -z "$out" ]
	[ -f "$CLAUDETOGGLE_HOME/state/devlog/sessions/$SID" ]
	got=$(CLAUDE_CWD="$CWD" CLAUDE_SESSION_ID="$SID" \
		bash -c '. "$1/bin/statusline.sh"; claudetoggle_statusline' _ "$CLAUDETOGGLE_HOME")
	[ "$got" = " │ devlog" ]
}

@test "second setup.sh run is byte-identical to the first" {
	cp "$CLAUDE_HOME/settings.json" "$TMP/before"
	bash "$REPO/setup.sh" --local="$REPO" >/dev/null
	diff "$TMP/before" "$CLAUDE_HOME/settings.json"
}

@test "claudetoggle list shows registered toggles" {
	got=$(ct list)
	[[ "$got" == *coauth* ]]
	[[ "$got" == *devlog* ]]
}

@test "uninstall removes wiring and preserves state" {
	dispatch UserPromptSubmit "$(p '/coauth')" >/dev/null
	ct uninstall >/dev/null
	[ ! -L "$CLAUDE_HOME/commands/coauth.md" ]
	[ ! -L "$CLAUDE_HOME/commands/devlog.md" ]
	! grep -q claudetoggle "$CLAUDE_HOME/settings.json"
	key=$(. "$REPO/lib/scope.sh" && project_key "$CWD")
	[ -f "$CLAUDETOGGLE_HOME/state/coauth/projects/$key" ]
}

@test "uninstall --purge removes the data home and the CLI" {
	ct uninstall --purge >/dev/null
	[ ! -d "$CLAUDETOGGLE_HOME" ]
	[ ! -e "$PREFIX/bin/claudetoggle" ]
}
