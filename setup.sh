#!/usr/bin/env sh
# claudetoggle setup — single install entry point.
#
#   curl -sSfL https://raw.githubusercontent.com/spuddydev/claudetoggle/main/setup.sh | sh
#   ./setup.sh --local      # use the current clone instead of fetching
#   ./setup.sh --version=v0.1.0
#
# Detects the latest tagged release (or main HEAD if none), downloads the
# tarball, places framework files under $XDG_DATA_HOME/claudetoggle, installs
# the claudetoggle CLI to $PREFIX/bin, and wires the dispatcher into
# $CLAUDE_HOME/settings.json.

set -eu

REPO=spuddydev/claudetoggle
TARBALL_BASE=https://github.com/$REPO/archive

CLAUDE_HOME=${CLAUDE_HOME:-$HOME/.claude}
CLAUDETOGGLE_HOME=${CLAUDETOGGLE_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claudetoggle}
PREFIX=${PREFIX:-$HOME/.local}
VERSION=${VERSION:-}
LOCAL=0
LOCAL_DIR=

while [ $# -gt 0 ]; do
	case $1 in
	--local) LOCAL=1 ;;
	--local=*)
		LOCAL=1
		LOCAL_DIR=${1#--local=}
		;;
	--version=*) VERSION=${1#--version=} ;;
	--prefix=*) PREFIX=${1#--prefix=} ;;
	-h | --help)
		cat <<EOF
claudetoggle setup

Usage: setup.sh [--local[=DIR]] [--version=vX.Y.Z] [--prefix=DIR]

Env: CLAUDE_HOME, CLAUDETOGGLE_HOME, XDG_DATA_HOME, PREFIX, VERSION

Without flags, fetches the latest release tarball from $REPO and installs.
With --local, uses the directory the script lives in (or =DIR) as the source.
EOF
		exit 0
		;;
	*)
		printf 'setup: unknown argument %s\n' "$1" >&2
		exit 2
		;;
	esac
	shift
done

say() {
	if [ -t 1 ]; then
		printf '\033[1m%s\033[0m\n' "$*"
	else
		printf '%s\n' "$*"
	fi
}

die() {
	printf 'setup: %s\n' "$*" >&2
	exit 1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

need bash
need jq

# ──── Resolve the source directory ────────────────────────────────────
src=
if [ "$LOCAL" -eq 1 ]; then
	if [ -n "$LOCAL_DIR" ]; then
		src=$(cd "$LOCAL_DIR" && pwd)
	else
		# When sourced from a clone, $0 points at the script's path.
		script_dir=$(cd "$(dirname "$0")" && pwd)
		src=$script_dir
	fi
	if [ ! -d "$src/lib" ] || [ ! -d "$src/bin" ]; then
		die "$src does not look like a claudetoggle clone (missing lib/ or bin/)."
	fi
	say "Using local source: $src"
else
	need tar
	need_curl_or_wget=
	if command -v curl >/dev/null 2>&1; then
		need_curl_or_wget=curl
	elif command -v wget >/dev/null 2>&1; then
		need_curl_or_wget=wget
	else
		die "neither curl nor wget is available."
	fi

	# Default version: try the latest tag via the GitHub API; fall back to
	# main if nothing is published yet.
	if [ -z "$VERSION" ]; then
		api_url=https://api.github.com/repos/$REPO/releases/latest
		if [ "$need_curl_or_wget" = curl ]; then
			latest=$(curl -sSfL "$api_url" 2>/dev/null | jq -r '.tag_name // empty' || true)
		else
			latest=$(wget -qO- "$api_url" 2>/dev/null | jq -r '.tag_name // empty' || true)
		fi
		if [ -n "$latest" ] && [ "$latest" != null ]; then
			VERSION=$latest
		else
			VERSION=main
		fi
	fi

	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT INT TERM
	tarball=$tmp/claudetoggle.tar.gz
	if [ "$VERSION" = main ]; then
		url=$TARBALL_BASE/refs/heads/main.tar.gz
	else
		url=$TARBALL_BASE/refs/tags/$VERSION.tar.gz
	fi
	say "Fetching $url"
	if [ "$need_curl_or_wget" = curl ]; then
		curl -sSfL "$url" -o "$tarball"
	else
		wget -qO "$tarball" "$url"
	fi
	tar -xzf "$tarball" -C "$tmp"
	# Tarballs unpack to a single top-level directory.
	src=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)
	[ -d "$src" ] || die "extraction produced no directory."
	[ -d "$src/lib" ] || die "$src is missing lib/. Wrong tarball?"
fi

# ──── Place framework files ───────────────────────────────────────────
mkdir -p \
	"$CLAUDETOGGLE_HOME/lib" \
	"$CLAUDETOGGLE_HOME/bin" \
	"$CLAUDETOGGLE_HOME/toggles" \
	"$CLAUDETOGGLE_HOME/examples" \
	"$CLAUDETOGGLE_HOME/state" \
	"$CLAUDE_HOME/commands" \
	"$PREFIX/bin"

cp -r "$src/lib"/. "$CLAUDETOGGLE_HOME/lib/"
cp -r "$src/bin"/. "$CLAUDETOGGLE_HOME/bin/"
cp -r "$src/scripts/settings_merge.sh" "$CLAUDETOGGLE_HOME/bin/settings_merge.sh"
if [ -d "$src/examples" ]; then
	cp -r "$src/examples"/. "$CLAUDETOGGLE_HOME/examples/"
fi
chmod +x "$CLAUDETOGGLE_HOME/bin"/*.sh "$CLAUDETOGGLE_HOME/bin/claudetoggle" 2>/dev/null || true

# Install the CLI on $PATH. Real copy, not a symlink.
cp "$CLAUDETOGGLE_HOME/bin/claudetoggle" "$PREFIX/bin/claudetoggle"
chmod +x "$PREFIX/bin/claudetoggle"

# Record the installed version.
printf '%s\n' "$VERSION" >"$CLAUDETOGGLE_HOME/VERSION"

# ──── Wire the dispatcher into settings.json (idempotent) ────────────
# Reuse settings_merge.sh helpers for consistency with the CLI's writes.
# shellcheck disable=SC1091
. "$CLAUDETOGGLE_HOME/bin/settings_merge.sh"
export CLAUDETOGGLE_HOME

settings_file=$CLAUDE_HOME/settings.json
settings_seed_if_missing "$settings_file"
if ! settings_check_valid "$settings_file"; then
	die "$settings_file is not valid JSON; refusing to edit."
fi
settings_with_lock settings_add_dispatch "$settings_file" "$CLAUDETOGGLE_HOME/bin"

# ──── Final summary ──────────────────────────────────────────────────
say
say 'claudetoggle is installed.'
printf '  data:     %s\n' "$CLAUDETOGGLE_HOME"
printf '  cli:      %s/bin/claudetoggle\n' "$PREFIX"
printf '  settings: %s\n' "$settings_file"
printf '  version:  %s\n\n' "$VERSION"

case ":$PATH:" in
*":$PREFIX/bin:"*) ;;
*)
	# shellcheck disable=SC2016
	printf 'NOTE: %s/bin is not on your $PATH. Add it to your shell config:\n' "$PREFIX"
	# shellcheck disable=SC2016
	printf '  export PATH="%s/bin:$PATH"\n\n' "$PREFIX"
	;;
esac

cat <<EOF
Next:
  claudetoggle add coauth      # register a shipped example
  claudetoggle list            # show registered toggles and state
  claudetoggle help            # full reference

Statusline integration (paste into your statusline script if you want indicators):
  . "$CLAUDETOGGLE_HOME/bin/statusline.sh"
  export CLAUDE_CWD="\$cwd" CLAUDE_SESSION_ID="\$session"
  left+="\$(claudetoggle_statusline)"
EOF
