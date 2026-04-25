# devlog

Per-session silent toggle. Asks Claude to keep a running journal under `.claude/devlog/` while the session is active.

- Silent flip: no announcement on `/devlog`. The statusline shows `devlog` while ON.
- Reannounces every twenty plain prompts so the rule stays in working memory.

Install:

```sh
cp -r examples/devlog ~/.claudetoggle/toggles/
./install.sh
```

Use `/devlog` to flip.
