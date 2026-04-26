#!/usr/bin/env bash
# Uninstall claudetoggle: remove dispatcher and per-toggle hook entries
# from $CLAUDE_HOME/settings.json (preserving any user-added entries),
# remove our deny rules, and unlink slash-command markdowns. Preserves
# $CLAUDETOGGLE_HOME/state by default; pass --purge to remove state and
# the home directory entirely.

set -o pipefail

claude_home=${CLAUDE_HOME:-$HOME/.claude}
toggle_home=${CLAUDETOGGLE_HOME:-$claude_home/toggles}
purge=0

while [ $# -gt 0 ]; do
	case $1 in
	--purge) purge=1 ;;
	-h | --help)
		cat <<EOF
Usage: uninstall.sh [--purge]

Removes claudetoggle entries from \$CLAUDE_HOME/settings.json and the
slash-command symlinks. State at \$CLAUDETOGGLE_HOME/state is preserved
by default. With --purge, the entire \$CLAUDETOGGLE_HOME tree is deleted.
EOF
		exit 0
		;;
	*)
		printf 'uninstall: unknown argument %s\n' "$1" >&2
		exit 2
		;;
	esac
	shift
done

repo_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
# shellcheck source=scripts/settings_merge.sh
. "$repo_dir/scripts/settings_merge.sh"

settings_file=$claude_home/settings.json

if [ ! -e "$settings_file" ]; then
	# Nothing to clean up in settings.json.
	:
elif ! settings_check_valid "$settings_file"; then
	printf 'uninstall: %s is not valid JSON; refusing to edit.\n' "$settings_file" >&2
	exit 2
else
	settings_with_lock settings_remove_tagged "$settings_file" "# claudetoggle:"
fi

# Remove slash-command symlinks and deny rules per registered toggle.
shopt -s nullglob
for dir in "$toggle_home"/*/; do
	dir=${dir%/}
	[ -r "$dir/toggle.sh" ] || continue
	name=$(basename "$dir")
	md=$claude_home/commands/$name.md
	if [ -L "$md" ]; then
		rm -f "$md"
	fi
	if [ -e "$settings_file" ] && settings_check_valid "$settings_file"; then
		mapfile -t rules < <(deny_globs_for_toggle "$name")
		settings_with_lock settings_remove_deny "$settings_file" "${rules[@]}"
	fi
done

if [ "$purge" -eq 1 ]; then
	rm -rf "$toggle_home"
	printf 'uninstall: removed %s\n' "$toggle_home"
else
	# Drop only the symlinks we manage; leave state and user toggles alone.
	rm -f "$toggle_home/.lib" "$toggle_home/.bin"
	printf 'uninstall: state preserved at %s/.state (use --purge to remove)\n' "$toggle_home"
fi
