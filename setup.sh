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
# Checksum verification when fetching a tagged release. Set
# CLAUDETOGGLE_SKIP_VERIFY=1 to opt out — useful when fetching `main`,
# bootstrapping a tag that pre-dates the release workflow, or running in
# an air-gapped environment.
SKIP_VERIFY=${CLAUDETOGGLE_SKIP_VERIFY:-0}

while [ $# -gt 0 ]; do
	case $1 in
	--local) LOCAL=1 ;;
	--local=*)
		LOCAL=1
		LOCAL_DIR=${1#--local=}
		;;
	--version=*) VERSION=${1#--version=} ;;
	--prefix=*) PREFIX=${1#--prefix=} ;;
	--skip-verify) SKIP_VERIFY=1 ;;
	-h | --help)
		cat <<EOF
claudetoggle setup

Usage: setup.sh [--local[=DIR]] [--version=vX.Y.Z] [--prefix=DIR] [--skip-verify]

Env: CLAUDE_HOME, CLAUDETOGGLE_HOME, XDG_DATA_HOME, PREFIX, VERSION,
     CLAUDETOGGLE_SKIP_VERIFY

Without flags, fetches the latest release tarball from $REPO and installs.
With --local, uses the directory the script lives in (or =DIR) as the source.
SHA256 verification runs by default for tagged releases; pass --skip-verify or
set CLAUDETOGGLE_SKIP_VERIFY=1 to bypass.
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

	# Verify the tarball against the SHA256SUMS attached to the GitHub release.
	# Only meaningful for tagged releases — `main` ships unsigned by definition.
	if [ "$VERSION" != main ] && [ "$SKIP_VERIFY" != 1 ]; then
		sums_url=https://github.com/$REPO/releases/download/$VERSION/SHA256SUMS
		sums_file=$tmp/SHA256SUMS
		say "Verifying $VERSION against $sums_url"
		fetched_sums=0
		if [ "$need_curl_or_wget" = curl ]; then
			if curl -sSfL "$sums_url" -o "$sums_file" 2>/dev/null; then fetched_sums=1; fi
		else
			if wget -qO "$sums_file" "$sums_url" 2>/dev/null; then fetched_sums=1; fi
		fi
		if [ "$fetched_sums" -eq 0 ]; then
			cat <<MSG >&2
setup: no SHA256SUMS published for $VERSION.

This release pre-dates the checksum workflow, or the upload failed. Re-run
with --skip-verify (or set CLAUDETOGGLE_SKIP_VERIFY=1) to install anyway.
MSG
			exit 1
		fi
		need sha256sum
		# The release workflow records the checksum against the basename
		# claudetoggle-<tag>.tar.gz, so rewrite the on-disk filename to match
		# before running sha256sum -c. Anchored to the second column of the
		# SHA256SUMS file to avoid matching unrelated entries.
		expected_name=claudetoggle-$VERSION.tar.gz
		cp "$tarball" "$tmp/$expected_name"
		(cd "$tmp" && sha256sum -c --strict --ignore-missing SHA256SUMS) >/dev/null || {
			printf 'setup: SHA256 verification FAILED for %s. Refusing to install.\n' "$VERSION" >&2
			exit 1
		}
		say 'Checksum OK.'
	fi

	tar -xzf "$tarball" -C "$tmp"
	# Tarballs unpack to a single top-level directory.
	src=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name 'claudetoggle-*' | head -n 1)
	[ -d "$src" ] || die "extraction produced no directory."
	[ -d "$src/lib" ] || die "$src is missing lib/. Wrong tarball?"
fi

# ──── Place framework files ───────────────────────────────────────────
mkdir -p \
	"$CLAUDETOGGLE_HOME/lib" \
	"$CLAUDETOGGLE_HOME/bin" \
	"$CLAUDETOGGLE_HOME/toggles" \
	"$CLAUDETOGGLE_HOME/examples" \
	"$CLAUDETOGGLE_HOME/docs" \
	"$CLAUDETOGGLE_HOME/state" \
	"$CLAUDE_HOME/commands" \
	"$CLAUDE_HOME/skills" \
	"$PREFIX/bin"

cp -r "$src/lib"/. "$CLAUDETOGGLE_HOME/lib/"
cp -r "$src/bin"/. "$CLAUDETOGGLE_HOME/bin/"
cp -r "$src/scripts/settings_merge.sh" "$CLAUDETOGGLE_HOME/bin/settings_merge.sh"
if [ -d "$src/examples" ]; then
	cp -r "$src/examples"/. "$CLAUDETOGGLE_HOME/examples/"
fi
if [ -d "$src/docs" ]; then
	cp -r "$src/docs"/. "$CLAUDETOGGLE_HOME/docs/"
fi
chmod +x "$CLAUDETOGGLE_HOME/bin"/*.sh "$CLAUDETOGGLE_HOME/bin/claudetoggle" 2>/dev/null || true

# ──── Install the create-claudetoggle skill (idempotent) ─────────────
# The skill teaches the model how to scaffold a new toggle. It is a plain
# markdown file; Claude Code picks it up at session start. We symlink so
# updates land automatically next time setup.sh runs.
if [ -d "$src/skills/create-claudetoggle" ]; then
	mkdir -p "$CLAUDETOGGLE_HOME/skills"
	cp -r "$src/skills/create-claudetoggle" "$CLAUDETOGGLE_HOME/skills/"
	skill_dst=$CLAUDE_HOME/skills/create-claudetoggle
	if [ -L "$skill_dst" ] || [ ! -e "$skill_dst" ]; then
		ln -snf "$CLAUDETOGGLE_HOME/skills/create-claudetoggle" "$skill_dst"
	fi
fi

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
