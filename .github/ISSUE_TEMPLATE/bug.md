---
name: Bug report
about: Something is wrong with claudetoggle
labels: bug
---

## What happened

<!-- A short description of the unexpected behaviour. -->

## Expected

<!-- What you thought would happen instead. -->

## Reproduce

<!-- Minimal steps. Toggle name, scope, command typed, and what showed up (or did not). -->

```
$ /yourtoggle
... output ...
```

## Environment

- claudetoggle version / commit: <!-- `git -C ~/projects/claudetoggle rev-parse --short HEAD` -->
- OS: <!-- e.g. Ubuntu 24.04, macOS 14 -->
- bash: <!-- `bash --version | head -1` -->
- jq: <!-- `jq --version` -->
- Claude Code: <!-- `claude --version` -->

## Debug log

<!-- Run with `CLAUDETOGGLE_DEBUG=1` and paste any relevant lines from `~/.claude/toggles/.debug.log`. Strip secrets. -->

```
... debug.log excerpt ...
```
