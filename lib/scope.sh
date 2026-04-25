#!/usr/bin/env bash
# Canonical state paths for toggles.
#
# Three scopes:
#   global   ~/.claude/<feature>/global[/...parts]
#   project  ~/.claude/<feature>/projects/<key>[/...parts]   key = sha256 of git root or cwd
#   session  ~/.claude/<feature>/sessions/<id>[/...parts]
#
# Helpers print paths. They never create directories — callers do that
# immediately before writing.

CLAUDETOGGLE_HOME="${CLAUDETOGGLE_HOME:-$HOME/.claude}"

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
	local base=$CLAUDETOGGLE_HOME/$feature path
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
