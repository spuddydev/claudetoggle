---
description: Toggle dev journaling for this session (writes to .claude/devlog/, untracked). User-invokable only.
---

<!-- devlog-toggle-marker -->

The user just typed `/devlog`. The dispatcher has already flipped the per-session sentinel. Acknowledge in one short line.

Do NOT run any bash to read or modify `~/.claudetoggle/state/devlog/*` — direct writes are blocked, and the toggle authority belongs solely to the user via `/devlog`.
