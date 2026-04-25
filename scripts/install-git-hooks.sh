#!/usr/bin/env bash
# Install local git hooks that run lint, format check, and the bats suite.
# Idempotent: re-running overwrites the previous symlinks.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
hooks_src=$repo_root/scripts/git-hooks
hooks_dst=$repo_root/.git/hooks

mkdir -p "$hooks_dst"
for hook in pre-commit pre-push; do
	ln -sf "$hooks_src/$hook" "$hooks_dst/$hook"
	chmod +x "$hooks_src/$hook"
	printf 'installed %s\n' "$hook"
done
