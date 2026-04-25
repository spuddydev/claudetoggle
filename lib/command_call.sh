#!/usr/bin/env bash
# Detect a slash-command invocation in a UserPromptSubmit prompt.
#
# command_called PROMPT CMD [MARKER]
#   PROMPT  the raw .prompt field from the hook input
#   CMD     command name without the leading slash, e.g. "coauth"
#   MARKER  optional substring expected in the slash-command markdown body
#           (e.g. "<!-- coauth-toggle-marker -->"). Lets a toggle author
#           ship a unique sentinel that is robust to harness changes.
#
# Returns 0 (matched) or 1.
#
# Three forms accepted, in order of how Claude Code currently sends them:
#
#   1. Trimmed prompt equals "/cmd" or starts with "/cmd " — user types
#      the command directly with no harness wrapping (older Claude Code,
#      raw API). Exact prefix match is safe because we anchor on /cmd.
#   2. Prompt CONTAINS "<command-name>/cmd</command-name>" — the wrapper
#      Claude Code currently emits. Appears on its own line surrounded by
#      sibling tags so it is never first in the prompt; anchoring would
#      break detection. The tag is specific enough that pasted content is
#      unlikely to collide.
#   3. Prompt CONTAINS MARKER — the slash command's markdown body has
#      been expanded into the prompt. Same anchoring caveat as form 2.
command_called() {
	local prompt=$1 cmd=$2 marker=${3:-}
	local trimmed=${prompt#"${prompt%%[![:space:]]*}"}
	trimmed=${trimmed%"${trimmed##*[![:space:]]}"}
	[[ $trimmed == "/$cmd" || $trimmed == "/$cmd "* || $trimmed == "/$cmd"$'\n'* ]] && return 0
	[[ $prompt == *"<command-name>/$cmd</command-name>"* ]] && return 0
	[[ -n $marker && $prompt == *"$marker"* ]] && return 0
	return 1
}
