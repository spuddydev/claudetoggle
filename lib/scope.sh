#!/usr/bin/env bash
# Canonical state paths for toggles.
#
# Layout (XDG-compliant):
#   $CLAUDETOGGLE_HOME/             default $XDG_DATA_HOME/claudetoggle (~/.local/share/claudetoggle)
#     lib/, bin/                    framework helpers and shipped binaries
#     toggles/<name>/               user toggles
#     examples/<name>/              shipped reference toggles
#     state/<feature>/...           sentinels and counters (this file's domain)
#     debug.log, settings.lock
#
# Three scopes for state under state/<feature>/:
#   global   state/<feature>/global[/...parts]
#   project  state/<feature>/projects/<key>[/...parts]   key = sha256 of git root or cwd
#   session  state/<feature>/sessions/<id>[/...parts]
#
# Helpers print paths. They never create directories — callers do that
# immediately before writing.

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CLAUDETOGGLE_HOME="${CLAUDETOGGLE_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claudetoggle}"

# project_key CWD → 16-char sha256 prefix of the git root (or CWD if not in
# a repo). Subdirectories of a repo therefore share project state.
project_key() {
	local dir=${1%/} top
	top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || true
	[ -n "$top" ] && dir=$top
	printf '%s' "$dir" | sha256sum | cut -c1-16
}

# scope_path SCOPE FEATURE CWD SESSION [...PARTS]
# Empty/missing required key prints nothing and returns 1, so callers can
# silently skip a toggle when its scope key isn't available.
scope_path() {
	local scope=$1 feature=$2 cwd=$3 session=$4
	shift 4
	local base=$CLAUDETOGGLE_HOME/state/$feature path
	case $scope in
	global) path=$base/global ;;
	project)
		[ -n "$cwd" ] || return 1
		path=$base/projects/$(project_key "$cwd")
		;;
	session)
		[ -n "$session" ] || return 1
		path=$base/sessions/$session
		;;
	*) return 1 ;;
	esac
	local part
	for part in "$@"; do path+=/$part; done
	printf '%s\n' "$path"
}
