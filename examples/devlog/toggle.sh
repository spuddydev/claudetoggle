#!/usr/bin/env bash
# devlog — silent session toggle that asks Claude to journal what it does
# in this session under .claude/devlog/. No model-facing announcement on
# flip; the statusline is the only visible indicator.
#
# shellcheck disable=SC2034
# All TOGGLE_* vars are read by the dispatcher when this file is sourced.

TOGGLE_API=1
TOGGLE_NAME=devlog
TOGGLE_SCOPE=session

TOGGLE_ON_MSG="devlog is ON for this session — keep a brief running journal of decisions, blockers and surprises. Append entries to .claude/devlog/ as you work; do not summarise the whole session at the end."
TOGGLE_OFF_MSG="devlog is OFF for this session."

TOGGLE_MARKER="<!-- devlog-toggle-marker -->"
TOGGLE_ANNOUNCE_ON_TOGGLE=0
TOGGLE_ANNOUNCE_ON_SESSION_START=1
TOGGLE_REANNOUNCE_EVERY=20

# Custom statusline fragment when devlog is ON.
toggle_devlog_statusline() {
	printf 'devlog'
}
