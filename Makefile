SHELL := /usr/bin/env bash

# All shell sources we own. find tolerates missing dirs; wildcard drops
# entries that do not exist on disk yet (install.sh, uninstall.sh).
SH_FILES := $(shell find lib bin examples scripts -name '*.sh' 2>/dev/null) bin/claudetoggle setup.sh uninstall.sh
SH_FILES := $(wildcard $(SH_FILES))

.PHONY: help test lint fmt fmt-check check hooks clean

help:
	@printf 'Targets:\n'
	@printf '  test       run bats tests\n'
	@printf '  lint       run shellcheck on all shell sources\n'
	@printf '  fmt        format shell sources with shfmt\n'
	@printf '  fmt-check  verify shell sources are formatted\n'
	@printf '  check      lint, fmt-check, test\n'
	@printf '  hooks      install local pre-commit and pre-push git hooks\n'
	@printf '  clean      remove test artefacts\n'

test:
	@if [ -d tests ] && ls tests/*.bats >/dev/null 2>&1; then \
		bats tests; \
	else \
		echo 'no bats tests yet'; \
	fi

lint:
	@if [ -n "$(SH_FILES)" ]; then \
		shellcheck $(SH_FILES); \
	else \
		echo 'no shell sources yet'; \
	fi

fmt:
	@if [ -n "$(SH_FILES)" ]; then shfmt -w $(SH_FILES); fi

fmt-check:
	@if [ -n "$(SH_FILES)" ]; then \
		shfmt -d $(SH_FILES); \
	else \
		echo 'no shell sources yet'; \
	fi

check: lint fmt-check test

hooks:
	bash scripts/install-git-hooks.sh

clean:
	rm -rf .bats-tmp
