#!/usr/bin/env bash
# Install claudetoggle into ~/.claudetoggle and wire its dispatcher into
# the Claude Code settings.json. Idempotent — running twice produces a
# byte-identical settings.json.
#
# Override paths with env vars:
#   CLAUDE_HOME         (default: $HOME/.claude)
#   CLAUDETOGGLE_HOME   (default: $HOME/.claudetoggle)
#   --prefix=DIR        repo location to symlink lib/ and bin/ from

set -o pipefail

repo_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
claude_home=${CLAUDE_HOME:-$HOME/.claude}
toggle_home=${CLAUDETOGGLE_HOME:-$claude_home/toggles}

while [ $# -gt 0 ]; do
	case $1 in
	--prefix=*) repo_dir=${1#--prefix=} ;;
	-h | --help)
		cat <<EOF
Usage: install.sh [--prefix=DIR]

Symlinks lib/ and bin/ from the repo into \$CLAUDETOGGLE_HOME and merges
the dispatcher entries into \$CLAUDE_HOME/settings.json. Re-run after
editing any registered toggle.sh, after pulling framework changes that
touch settings.json shape, or after adding a TOGGLE_EXTRA_HOOKS entry.
EOF
		exit 0
		;;
	*)
		printf 'install: unknown argument %s\n' "$1" >&2
		exit 2
		;;
	esac
	shift
done

# shellcheck source=scripts/settings_merge.sh
. "$repo_dir/scripts/settings_merge.sh"
# shellcheck source=lib/scope.sh
. "$repo_dir/lib/scope.sh"

settings_file=$claude_home/settings.json

mkdir -p "$toggle_home/.state" "$claude_home/commands"

# Copy the framework's lib/ and bin/ into the toggle home as real files,
# dot-prefixed so they sit alongside user toggle directories without
# colliding with the registry glob ($home/*/toggle.sh). Re-running
# install.sh re-copies, which is the documented upgrade path after
# `git pull`. We rm-rf first so a removed file in the repo also goes.
rm -rf "$toggle_home/.lib" "$toggle_home/.bin"
cp -r "$repo_dir/lib" "$toggle_home/.lib"
cp -r "$repo_dir/bin" "$toggle_home/.bin"
chmod +x "$toggle_home/.bin"/*.sh

settings_seed_if_missing "$settings_file"
if ! settings_check_valid "$settings_file"; then
	printf 'install: %s is not valid JSON; refusing to edit.\n' "$settings_file" >&2
	exit 2
fi

install_one_toggle() {
	local dir=$1
	local name
	name=$(basename "$dir")
	local toggle_sh=$dir/toggle.sh
	[ -r "$toggle_sh" ] || return 0

	local rc=0
	(
		# shellcheck disable=SC1090
		. "$toggle_sh"
		[ "${TOGGLE_NAME:-}" = "$name" ] || {
			printf 'install: %s declares TOGGLE_NAME=%q; expected %s. Skipped.\n' \
				"$toggle_sh" "${TOGGLE_NAME:-}" "$name" >&2
			exit 1
		}
		[ "${TOGGLE_API:-}" = "1" ] || {
			printf 'install: %s declares TOGGLE_API=%q; only 1 supported. Skipped.\n' \
				"$toggle_sh" "${TOGGLE_API:-<unset>}" >&2
			exit 1
		}
	) || rc=$?
	[ "$rc" -eq 0 ] || return 0

	# Slash-command markdown.
	local md_src=$dir/$name.md
	local md_dst=$claude_home/commands/$name.md
	if [ -r "$md_src" ]; then
		if [ -L "$md_dst" ] || [ ! -e "$md_dst" ]; then
			ln -snf "$md_src" "$md_dst"
		else
			printf 'install: %s exists and is not a symlink; skipping.\n' "$md_dst" >&2
		fi
	fi

	# permissions.deny templates and TOGGLE_EXTRA_HOOKS.
	# Source again for the parent shell so we can read the arrays.
	# shellcheck disable=SC2034  # vars are read by sourced toggle.sh
	local TOGGLE_NAME TOGGLE_API
	local TOGGLE_EXTRA_HOOKS=()
	# shellcheck disable=SC1090
	. "$toggle_sh"

	# Deny rules.
	local rules=()
	while IFS= read -r line; do
		rules+=("$line")
	done < <(deny_globs_for_toggle "$name")
	settings_with_lock settings_add_deny "$settings_file" "${rules[@]}"

	# Extra hooks.
	local idx=0 entry event matcher if_clause script script_path
	for entry in "${TOGGLE_EXTRA_HOOKS[@]}"; do
		IFS=$'\x1f' read -r event matcher if_clause script <<<"$entry"
		script_path=$toggle_home/$name/$script
		settings_with_lock settings_add_extra_hook \
			"$settings_file" "$name" "$idx" \
			"$event" "$matcher" "$if_clause" "$script_path"
		idx=$((idx + 1))
	done
}

shopt -s nullglob
for dir in "$toggle_home"/*/; do
	dir=${dir%/}
	# Skip dotted siblings (.lib, .bin, .state) and any dir without toggle.sh.
	[ -r "$dir/toggle.sh" ] || continue
	install_one_toggle "$dir"
done

settings_with_lock settings_add_dispatch "$settings_file" "$toggle_home/.bin"

# statusLine integration: do NOT mutate the user's statusLine.command.
# Detect whether the user's statusline already sources our snippet; if
# not, print the integration block they should add and where.
sl_cmd=$(jq -r '.statusLine.command // ""' "$settings_file" 2>/dev/null)
sl_target=
case $sl_cmd in
bash\ \"*\")
	# Strip surrounding bash " and the trailing "
	sl_target=${sl_cmd#bash \"}
	sl_target=${sl_target%\"}
	sl_target=${sl_target/#\$HOME/$HOME}
	sl_target=${sl_target/#~/$HOME}
	;;
esac
sl_already_wired=0
if [ -n "$sl_target" ] && [ -r "$sl_target" ] &&
	grep -q claudetoggle_statusline "$sl_target" 2>/dev/null; then
	sl_already_wired=1
fi
if [ "$sl_already_wired" -eq 0 ]; then
	cat <<EOF

claudetoggle is installed.
${sl_target:+To enable the statusline indicator, add the following to $sl_target:}${sl_target:-Set statusLine.command in $settings_file to a script that sources statusline.sh, or add it to your existing statusline. Example snippet:}

  . "$toggle_home/.bin/statusline.sh"
  export CLAUDE_CWD="\$cwd" CLAUDE_SESSION_ID="\$session"
  left+="\$(claudetoggle_statusline)"

EOF
fi
