#!/usr/bin/env bats
# End-to-end: install → drive the dispatcher with stdin JSON → render the
# statusline → uninstall. Validates that the pieces integrate.

load test_helper

setup() {
	export TMP=$(mktemp -d)
	export HOME=$TMP
	export CLAUDE_HOME=$TMP/.claude
	export CLAUDETOGGLE_HOME=$CLAUDE_HOME/toggles
	export REPO=$(repo_root)
	export CWD=$TMP/work
	export SID=e2e-1
	mkdir -p "$CWD" "$CLAUDETOGGLE_HOME/coauth" "$CLAUDETOGGLE_HOME/devlog"
	cat >"$CLAUDETOGGLE_HOME/coauth/toggle.sh" <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=coauth
TOGGLE_SCOPE=project
TOGGLE_ON_MSG="coauth ON for this project"
TOGGLE_OFF_MSG="coauth OFF"
TOGGLE_MARKER="<!-- coauth-marker -->"
TOGGLE_REANNOUNCE_EVERY=2
EOF
	cat >"$CLAUDETOGGLE_HOME/coauth/coauth.md" <<'EOF'
---
description: Toggle coauth
---
<!-- coauth-marker -->
EOF
	cat >"$CLAUDETOGGLE_HOME/devlog/toggle.sh" <<'EOF'
TOGGLE_API=1
TOGGLE_NAME=devlog
TOGGLE_SCOPE=session
TOGGLE_ON_MSG="devlog ON"
TOGGLE_OFF_MSG="devlog OFF"
TOGGLE_ANNOUNCE_ON_TOGGLE=0
toggle_devlog_statusline() { printf 'devlog (live)'; }
EOF
	cat >"$CLAUDETOGGLE_HOME/devlog/devlog.md" <<'EOF'
---
description: Toggle devlog
---
EOF
	bash "$REPO/install.sh" >/dev/null
}

teardown() {
	[ -n "$TMP" ] && rm -rf "$TMP"
}

dispatch() {
	local event=$1 input=$2
	printf %s "$input" | bash "$CLAUDETOGGLE_HOME/.bin/dispatch.sh" "$event"
}

p() {
	jq -nc --arg p "$1" --arg c "$CWD" --arg s "$SID" \
		'{hook_event_name:"UserPromptSubmit",prompt:$p,cwd:$c,session_id:$s}'
}

s() {
	jq -nc --arg c "$CWD" --arg s "$SID" \
		'{hook_event_name:"SessionStart",cwd:$c,session_id:$s}'
}

@test "install copies framework lib and bin; symlinks slash-command markdowns" {
	[ -d "$CLAUDETOGGLE_HOME/.lib" ]
	[ -f "$CLAUDETOGGLE_HOME/.lib/toggle.sh" ]
	[ -f "$CLAUDETOGGLE_HOME/.bin/dispatch.sh" ]
	[ -L "$CLAUDE_HOME/commands/coauth.md" ]
	[ -L "$CLAUDE_HOME/commands/devlog.md" ]
	jq -e '.permissions.deny | any(. == "Bash(touch *.claude/toggles/.state/coauth/*)")' "$CLAUDE_HOME/settings.json"
	jq -e '.permissions.deny | any(. == "Bash(touch *.claude/toggles/.state/devlog/*)")' "$CLAUDE_HOME/settings.json"
}

@test "/coauth flips ON, sentinel created, block reason matches ON_MSG" {
	out=$(dispatch UserPromptSubmit "$(p '/coauth')")
	[ "$(jq -r .reason <<<"$out")" = "coauth ON for this project" ]
	key=$(. "$REPO/lib/scope.sh" && project_key "$CWD")
	[ -f "$CLAUDETOGGLE_HOME/.state/coauth/projects/$key" ]
}

@test "plain prompt after flip-on does NOT reannounce until threshold" {
	dispatch UserPromptSubmit "$(p '/coauth')" >/dev/null
	# REANNOUNCE_EVERY=2; counter seeded to 1; first plain prompt ticks → 2 → due
	out=$(dispatch UserPromptSubmit "$(p 'plain one')")
	[ -n "$out" ]
	[[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")" == *"coauth"* ]]
	# Second plain prompt: counter resets to 0, tick → 1 → not due
	out=$(dispatch UserPromptSubmit "$(p 'plain two')")
	[ -z "$out" ]
}

@test "SessionStart after flip-on emits ON_MSG to stdout (not JSON)" {
	dispatch UserPromptSubmit "$(p '/coauth')" >/dev/null
	out=$(dispatch SessionStart "$(s)")
	[[ "$out" == *"coauth ON for this project"* ]]
	! jq -e . <<<"$out" >/dev/null 2>&1
}

@test "/devlog flips silently (no announce); statusline reflects custom indicator" {
	out=$(dispatch UserPromptSubmit "$(p '/devlog')")
	[ -z "$out" ]
	[ -f "$CLAUDETOGGLE_HOME/.state/devlog/sessions/$SID" ]
	got=$(CLAUDE_CWD="$CWD" CLAUDE_SESSION_ID="$SID" bash -c '. "$1/.bin/statusline.sh"; claudetoggle_statusline' _ "$CLAUDETOGGLE_HOME")
	[ "$got" = " │ devlog (live)" ]
}

@test "second install run is byte-identical" {
	cp "$CLAUDE_HOME/settings.json" "$TMP/before"
	bash "$REPO/install.sh" >/dev/null
	diff "$TMP/before" "$CLAUDE_HOME/settings.json"
}

@test "uninstall (default) removes settings entries; preserves state" {
	dispatch UserPromptSubmit "$(p '/coauth')" >/dev/null
	bash "$REPO/uninstall.sh" >/dev/null
	[ ! -L "$CLAUDE_HOME/commands/coauth.md" ]
	[ ! -L "$CLAUDE_HOME/commands/devlog.md" ]
	! grep -q claudetoggle "$CLAUDE_HOME/settings.json"
	# State preserved
	key=$(. "$REPO/lib/scope.sh" && project_key "$CWD")
	[ -f "$CLAUDETOGGLE_HOME/.state/coauth/projects/$key" ]
}

@test "uninstall --purge removes the entire home" {
	bash "$REPO/uninstall.sh" --purge >/dev/null
	[ ! -d "$CLAUDETOGGLE_HOME" ]
}
