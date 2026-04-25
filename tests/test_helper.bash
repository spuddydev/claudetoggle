# Shared bats helper: per-test isolated $CLAUDETOGGLE_HOME and lib loader.

setup_isolated_home() {
	CLAUDETOGGLE_HOME=$(mktemp -d)
	export CLAUDETOGGLE_HOME
}

teardown_isolated_home() {
	if [ -n "${CLAUDETOGGLE_HOME:-}" ] && [ -d "$CLAUDETOGGLE_HOME" ]; then
		rm -rf "$CLAUDETOGGLE_HOME"
	fi
}

repo_root() {
	cd "$BATS_TEST_DIRNAME/.." && pwd
}

load_lib() {
	local root
	root=$(repo_root)
	# shellcheck disable=SC1091
	. "$root/lib/$1.sh"
}
