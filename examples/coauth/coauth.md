---
description: Toggle Co-Authored-By trailer policy for this project (per-project, persists across sessions). User-invokable only.
---

<!-- coauth-toggle-marker -->

The user just typed `/coauth`. The dispatcher has already flipped the per-project sentinel and announced the new state for this turn. Acknowledge in one short line.

Do NOT run any bash to read or modify `~/.claude/toggles/.state/coauth/*` — direct writes are blocked, and the toggle authority belongs solely to the user via `/coauth`.
