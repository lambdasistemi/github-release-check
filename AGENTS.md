# Repository Agent Guide

## What this repo is

`github-release-check` is a small Haskell library that prints an update
banner on stderr when a CLI is behind its latest GitHub release. It
wraps a CLI's `main` (via `withCli` / `withUpdateCheck`), polls the
GitHub Releases API for the latest tag, and — rate-limited by an on-disk
JSON cache with two independent timers — emits a two-line banner when a
newer version exists. Every failure path is silent; the check never
throws and never changes the wrapped action's exit code. The optional
`--version` flag lives in a separate `github-release-check:optparse`
sublibrary so banner-only consumers avoid the `optparse-applicative`
dependency. A `github-release-check-canary` executable dogfoods the
whole IO path against this repository and runs in CI.

## How to work here

All commands run inside `nix develop --quiet` (haskell.nix, GHC 9.12.3):

- Build: `just build` (`cabal build all -O0 --enable-tests`)
- Test: `just unit` (`cabal test unit-tests -O0`); narrow with
  `just unit "<hspec match>"`
- Format: `just format` (fourmolu + cabal-fmt + nixfmt)
- Lint: `just hlint`
- Full CI mirror: `nix flake check` (build + unit + lint + canary)
- Live canary against the real GitHub API: `nix run .#canary`
  (and `nix run .#canary -- --version`)

Source lives in `lib/` (core library), `lib-optparse/` (the `optparse`
sublibrary), `app/canary/` (the canary executable), and `test/`
(hspec). Keep changes Hackage-ready (`cabal check`), Haddock every
export, and follow the fourmolu style (leading commas/arrows).

## Skills

Activatable procedures live under `skills/`. Load the one whose
description matches your task:

- `skills/github-release-check-guide/` — repository map, verified
  build/test/run commands, where each piece of logic lives, how to use
  the library and its `--version` sublibrary, and where the answers to
  common questions live.

## First-run setup

None. This is a self-contained library with no operator-specific
configuration; clone, enter `nix develop`, and the commands above work.
