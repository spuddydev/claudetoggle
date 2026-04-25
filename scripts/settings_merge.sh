#!/usr/bin/env bash
# Settings.json merge helpers shared by install.sh and uninstall.sh.
# shellcheck disable=SC2016
# Single-quoted jq expressions are intentional; we pass shell values via --arg.
#
# Invariants:
# - jq is invoked with --indent 2 everywhere; output is written through a
#   tempfile + mv so concurrent readers see either old or new contents.
# - Hook entries that claudetoggle owns are tagged via a literal sentinel
#   substring inside the "command" string, e.g.
#       bash "$HOME/.claudetoggle/bin/dispatch.sh" UserPromptSubmit # claudetoggle:dispatch
#   The shell parses # as a comment at execution time, so the tag is
#   harmless when the command runs and stable for jq string-match lookup.
# - permissions.deny is append-only and dedup-by-rule-string. No alphabetic
#   re-sort, so user-edited order is preserved across runs.

settings_seed_if_missing() {
	local f=$1
	[ -e "$f" ] && return 0
	mkdir -p "$(dirname "$f")"
	printf '{}\n' >"$f"
}

settings_check_valid() {
	local f=$1
	jq empty "$f" >/dev/null 2>&1
}

# settings_atomic_write FILE EXPR [JQ_ARG...]
# Run jq with the given expression and arguments, writing through a tempfile.
settings_atomic_write() {
	local f=$1 expr=$2
	shift 2
	local tmp
	tmp=$(mktemp "$f.XXXXXX") || return 1
	if ! jq --indent 2 "$@" "$expr" "$f" >"$tmp"; then
		rm -f "$tmp"
		return 1
	fi
	mv "$tmp" "$f"
}

# settings_lock_path
# Lock file location, kept inside our own home rather than $CLAUDE_HOME/.
settings_lock_path() {
	printf '%s\n' "${CLAUDETOGGLE_HOME:-$HOME/.claudetoggle}/.settings.lock"
}

# settings_with_lock CMD ARGS...
# Execute CMD ARGS... while holding an exclusive flock on the lock file.
# Test-only env hook CLAUDETOGGLE_INSTALL_SLEEP introduces a deterministic
# pause AFTER acquiring the lock so two backgrounded installs interleave.
settings_with_lock() {
	local lock
	lock=$(settings_lock_path)
	mkdir -p "$(dirname "$lock")"
	(
		flock 9
		if [ -n "${CLAUDETOGGLE_INSTALL_SLEEP:-}" ]; then
			sleep "$CLAUDETOGGLE_INSTALL_SLEEP"
		fi
		"$@"
	) 9>"$lock"
}

# settings_has_dispatch FILE → 0 if the dispatch sentinel is already present.
settings_has_dispatch() {
	jq -e --arg t '# claudetoggle:dispatch' \
		'[.. | objects | select(has("command")) | .command | tostring | select(contains($t))] | length > 0' \
		"$1" >/dev/null 2>&1
}

# settings_add_dispatch FILE BIN_DIR
# Append the dispatcher entry under hooks.UserPromptSubmit[0].hooks and
# hooks.SessionStart[0].hooks if no entry tagged claudetoggle:dispatch
# already exists.
settings_add_dispatch() {
	local f=$1 bin=$2
	settings_has_dispatch "$f" && return 0
	settings_atomic_write "$f" '
        .hooks //= {}
        | .hooks.UserPromptSubmit //= [{"hooks":[]}]
        | .hooks.SessionStart //= [{"hooks":[]}]
        | (.hooks.UserPromptSubmit[0].hooks //= [])
        | (.hooks.SessionStart[0].hooks //= [])
        | .hooks.UserPromptSubmit[0].hooks += [{
            type:"command",
            command:("bash \"" + $bin + "/dispatch.sh\" UserPromptSubmit # claudetoggle:dispatch"),
            timeout:5,
            statusMessage:"claudetoggle"
          }]
        | .hooks.SessionStart[0].hooks += [{
            type:"command",
            command:("bash \"" + $bin + "/dispatch.sh\" SessionStart # claudetoggle:dispatch"),
            timeout:5
          }]
    ' --arg bin "$bin"
}

# settings_add_extra_hook FILE NAME IDX EVENT MATCHER IF SCRIPT_PATH
# Append one TOGGLE_EXTRA_HOOKS entry. Skip if the corresponding sentinel
# (claudetoggle:NAME:IDX) is already present in any hook command.
settings_add_extra_hook() {
	local f=$1 name=$2 idx=$3 event=$4 matcher=$5 if_clause=$6 script=$7
	local sentinel="# claudetoggle:$name:$idx"
	if jq -e --arg t "$sentinel" \
		'[.. | objects | select(has("command")) | .command | tostring | select(contains($t))] | length > 0' \
		"$f" >/dev/null 2>&1; then
		return 0
	fi
	# Build the entry with optional fields conditionally included.
	local cmd
	cmd="bash \"$script\" $sentinel"
	settings_atomic_write "$f" '
        .hooks //= {}
        | (.hooks[$ev] //= [])
        | (
            ([.hooks[$ev][] | select(.matcher == $m)] | length) as $found
            | if $found == 0 then
                .hooks[$ev] += [({matcher:$m, hooks:[]} | if $i != "" then . + {} else . end)]
              else . end
          )
        | (.hooks[$ev] |= map(
            if .matcher == $m then
              .hooks //= []
              | .hooks += [
                  ({type:"command", command:$cmd, timeout:5}
                   | if $i != "" then . + {if:$i} else . end)
                ]
            else . end))
    ' --arg ev "$event" --arg m "$matcher" --arg i "$if_clause" --arg cmd "$cmd"
}

# settings_add_deny FILE RULES...
# Append rule strings to permissions.deny[] only if absent (string-equality).
settings_add_deny() {
	local f=$1
	shift
	[ "$#" -eq 0 ] && return 0
	local r
	for r in "$@"; do
		if ! jq -e --arg r "$r" '(.permissions.deny // []) | index($r)' "$f" >/dev/null 2>&1; then
			settings_atomic_write "$f" '
                .permissions //= {}
                | (.permissions.deny //= [])
                | .permissions.deny += [$r]
            ' --arg r "$r"
		fi
	done
}

# settings_remove_tagged FILE TAG
# Remove every hook entry whose command contains TAG; prune any matcher
# block whose hooks array becomes empty; prune any event array that becomes
# empty; finally prune .hooks if empty.
settings_remove_tagged() {
	local f=$1 tag=$2
	settings_atomic_write "$f" '
        if .hooks then
          .hooks |= with_entries(
            .value |= (
              map(
                .hooks |= map(select(((.command // "") | tostring | contains($t)) | not))
                | select((.hooks // []) | length > 0)
              )
            )
          )
          | .hooks |= with_entries(select((.value | length) > 0))
          | (if (.hooks | length) == 0 then del(.hooks) else . end)
        else . end
    ' --arg t "$tag"
}

# settings_remove_deny FILE RULES...
# Remove specific deny rule strings.
settings_remove_deny() {
	local f=$1
	shift
	[ "$#" -eq 0 ] && return 0
	local r
	for r in "$@"; do
		settings_atomic_write "$f" '
            if (.permissions.deny // []) | index($r)
              then .permissions.deny |= map(select(. != $r))
              else . end
            | (if (.permissions.deny // []) == [] then del(.permissions.deny) else . end)
            | (if (.permissions // {}) == {} then del(.permissions) else . end)
        ' --arg r "$r"
	done
}

# deny_globs_for_toggle NAME → print one Bash deny rule per write verb
# targeting *.claudetoggle/state/<name>/*. The single broad glob covers
# both sentinels and counters.
deny_globs_for_toggle() {
	local name=$1 verb
	local target="*.claudetoggle/state/$name/*"
	for verb in touch rm rmdir mv cp chmod ln tee; do
		printf 'Bash(%s %s)\n' "$verb" "$target"
	done
	printf 'Bash(* > %s)\n' "$target"
	printf 'Bash(* >> %s)\n' "$target"
}
