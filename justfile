# shellcheck shell=bash

set unstable := true

# List available recipes
default:
    @just --list

# Format Haskell, cabal and nix files
format:
    #!/usr/bin/env bash
    set -euo pipefail
    for _ in {1..3}; do
        fourmolu -i lib lib-optparse test
    done
    cabal-fmt -i github-release-check.cabal
    nixfmt flake.nix nix/*.nix

# Check formatting (CI / pre-push gate)
format-check:
    #!/usr/bin/env bash
    set -euo pipefail
    fourmolu -m check lib lib-optparse test
    diff -u github-release-check.cabal \
        <(cabal-fmt github-release-check.cabal)

# Run hlint
hlint:
    #!/usr/bin/env bash
    hlint lib lib-optparse test

# Build the library
build:
    #!/usr/bin/env bash
    cabal build all -O0 --enable-tests

# Run unit tests (optional --match)
unit match="":
    #!/usr/bin/env bash
    if [[ '{{ match }}' == "" ]]; then
        cabal test unit-tests -O0 --test-show-details=direct
    else
        cabal test unit-tests -O0 --test-show-details=direct \
            --test-option=--match --test-option="{{ match }}"
    fi

# Full CI loop (mirrors flake checks)
ci:
    #!/usr/bin/env bash
    set -euo pipefail
    nix flake check --no-eval-cache
