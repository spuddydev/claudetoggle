# claudetoggle

Tiny framework for building toggleable Claude Code hooks ("togglehooks") that are fast, low-token, and uniformly wired.

Status: early. See [issues](../../issues) for the roadmap.

## What it does

- One file per toggle declares its name, scope, on and off messages, and reannounce policy.
- A generic dispatcher hooks `UserPromptSubmit` and `SessionStart` once and drives every registered toggle.
- A statusline snippet shows nothing when all toggles are off, and a compact list when any are on.
- An install script wires it into `~/.claude/settings.json` idempotently. Uninstall reverses it.

## License

MIT. See [LICENSE](LICENSE).
