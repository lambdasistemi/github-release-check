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

# Canary live-boundary smoke (S3): exercises the built executable's
# actual argv parsing, env read, exit code, and stdout shape — the
# unit suite cannot catch a regression in Main.hs wiring.
canary_no_args="$(nix develop --quiet -c cabal run -v0 -O0 github-release-check-canary)"
canary_no_args_lines="$(printf '%s' "$canary_no_args" | wc -l)"
[ "$canary_no_args_lines" = "0" ] || { echo "canary smoke: expected 1 stdout line, got more"; printf '%s\n' "$canary_no_args"; exit 1; }
case "$canary_no_args" in
    "github-release-check-canary "*)  : ;;
    *)
        echo "canary smoke: stdout did not start with 'github-release-check-canary '"
        printf '%s\n' "$canary_no_args"
        exit 1
        ;;
esac

canary_version="$(nix develop --quiet -c cabal run -v0 -O0 github-release-check-canary -- --version)"
canary_version_first_line="$(printf '%s\n' "$canary_version" | head -1)"
printf '%s\n' "$canary_version_first_line" \
    | grep -qE '^github-release-check-canary [0-9]+(\.[0-9]+)*$' \
    || { echo "canary --version line mismatch: $canary_version_first_line"; exit 1; }
