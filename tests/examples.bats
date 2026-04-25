#!/usr/bin/env bats
# Validate every example toggle: parses, sources cleanly, declares all the
# required vars, and TOGGLE_NAME matches its directory.

load test_helper

examples_dir() {
	printf '%s\n' "$(repo_root)/examples"
}

@test "examples/coauth/toggle.sh parses with bash -n" {
	bash -n "$(examples_dir)/coauth/toggle.sh"
}

@test "examples/coauth/toggle.sh sources cleanly with all required vars" {
	got=$(bash -c '
        . "$1/coauth/toggle.sh"
        printf "%s|%s|%s|%s|%s|%s\n" \
            "${TOGGLE_API:-}" "${TOGGLE_NAME:-}" "${TOGGLE_SCOPE:-}" \
            "${TOGGLE_ON_MSG:+set}" "${TOGGLE_OFF_MSG:+set}" "${TOGGLE_MARKER:+set}"
    ' _ "$(examples_dir)")
	[ "$got" = "1|coauth|project|set|set|set" ]
}

@test "examples/coauth: TOGGLE_NAME matches dirname; <name>.md has marker" {
	. "$(examples_dir)/coauth/toggle.sh"
	[ "$TOGGLE_NAME" = "coauth" ]
	grep -q "$TOGGLE_MARKER" "$(examples_dir)/coauth/coauth.md"
}

@test "examples/devlog/toggle.sh parses and declares custom statusline fn" {
	bash -n "$(examples_dir)/devlog/toggle.sh"
	got=$(bash -c '
        . "$1/devlog/toggle.sh"
        if declare -F toggle_devlog_statusline >/dev/null; then printf "yes"; else printf "no"; fi
    ' _ "$(examples_dir)")
	[ "$got" = "yes" ]
}

@test "examples/devlog: silent toggle with marker present in markdown" {
	. "$(examples_dir)/devlog/toggle.sh"
	[ "$TOGGLE_NAME" = "devlog" ]
	[ "$TOGGLE_ANNOUNCE_ON_TOGGLE" = "0" ]
	grep -q "$TOGGLE_MARKER" "$(examples_dir)/devlog/devlog.md"
}
