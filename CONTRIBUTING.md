# Contributing

Thanks for considering a patch. This page is for hacking on the framework. If you're authoring a toggle, see [README.md](README.md) instead.

## Workflow

- Branch per change. Open a pull request when ready.
- `main` is protected: PR-only, squash merge, required CI checks `lint` and `test`, no bypass.
- Re-merge by squash. The squashed commit lands on `main`; feature branches are deleted on merge.

## One-time setup

```sh
git clone https://github.com/spuddydev/claudetoggle
cd claudetoggle
make hooks
```

`make hooks` installs local pre-commit (lint + format check on staged shell files) and pre-push (full bats suite) hooks.

## Install bats

The pre-push hook silently skips when `bats` is missing — CI catches the gap regardless, but local feedback is faster:

- Debian / Ubuntu: `sudo apt install bats`
- macOS: `brew install bats-core`
- From source: `git clone https://github.com/bats-core/bats-core` and run via `bats-core/bin/bats`

## Before pushing

```sh
make check    # lint, fmt-check, test
```

If you only touched specific files, `shellcheck path/to/file.sh` and `shfmt -d path/to/file.sh` are quick spot-checks.

## Style

House style is **British English** for prose and code-emitted strings (organise, behaviour, colour). Outside contributors writing US English are welcome; copy may be normalised on merge.

### Commits

- Plain words, no symbols. `+` becomes "and"; em dashes are minimised.
- No code-speak — no function names, file names, flag names. Reviewers will read the diff for "what".
- Prefer short bullets to long sentences.
- Header <=50 characters.

### Pull requests

- Concise. Short summary, short bullets, no padding.
- Code-speak is fine in PRs when unavoidable for clarity.
- A test-plan checklist is welcome but not required.
