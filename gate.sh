#!/usr/bin/env bash
# Pre-push and pre-commit gate for PR #4 (issue #3 — withCli + versionOption).
# Subagents MUST run ./gate.sh and observe success before returning a commit.
# Removed in the final `chore: drop gate.sh (ready for review)` commit before
# the PR is marked ready.
set -euo pipefail

git diff --check

nix develop --quiet -c just build
nix develop --quiet -c just unit
nix develop --quiet -c just format-check
nix develop --quiet -c just hlint
