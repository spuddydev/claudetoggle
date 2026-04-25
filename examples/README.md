# Examples

Reference toggles. Not auto-installed: copy the directory you want into `~/.claude/toggles/` and re-run `./install.sh`.

- **coauth** (project scope) — flips a `Co-Authored-By: Claude` trailer policy for the current project. Demonstrates a registry file plus a peer `commit-check.sh` script declared via `TOGGLE_EXTRA_HOOKS`.
- **devlog** (session scope, silent) — sentinels a "journal what you do this session" rule. Demonstrates `TOGGLE_ANNOUNCE_ON_TOGGLE=0` (silent flips) and a custom `toggle_devlog_statusline` function.

```sh
cp -r examples/coauth ~/.claude/toggles/
./install.sh
```

Each example has its own `README.md` with the specific behaviour and any caveats.
