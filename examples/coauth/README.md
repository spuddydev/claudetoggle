# coauth

Per-project toggle for the `Co-Authored-By: Claude <noreply@anthropic.com>` commit trailer.

- ON: require the trailer; allow a multi-line body; keep the header <=50 characters.
- OFF: refuse the trailer; reject any body; single-line conventional header.

The peer `commit-check.sh` runs as a `PreToolUse(Bash)` hook on `git commit *` and denies the call when the message violates the current state.

Install:

```sh
cp -r examples/coauth ~/.claude/toggles/
./install.sh
```

Use `/coauth` to flip.
