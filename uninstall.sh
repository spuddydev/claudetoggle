#!/usr/bin/env bash
# Convenience wrapper: forwards to `claudetoggle uninstall`.
# Pass --purge to also delete data and state. The CLI itself is
# typically reached as `claudetoggle uninstall` after install.

set -o pipefail

PREFIX=${PREFIX:-$HOME/.local}
CLAUDETOGGLE_HOME=${CLAUDETOGGLE_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claudetoggle}

if command -v claudetoggle >/dev/null 2>&1; then
	exec claudetoggle uninstall "$@"
elif [ -x "$PREFIX/bin/claudetoggle" ]; then
	exec "$PREFIX/bin/claudetoggle" uninstall "$@"
elif [ -x "$CLAUDETOGGLE_HOME/bin/claudetoggle" ]; then
	exec "$CLAUDETOGGLE_HOME/bin/claudetoggle" uninstall "$@"
else
	printf 'uninstall: claudetoggle is not installed.\n' >&2
	exit 1
fi
