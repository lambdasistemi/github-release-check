# Implementation Plan: `withCli` + `versionOption` helpers

**Branch**: `001-withcli-helpers` | **Date**: 2026-05-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `specs/001-withcli-helpers/spec.md`

## Summary

Add two consumer-side helpers to `github-release-check`:

- **`withCli`** in a new module `GitHub.Release.Check.Cli` (re-exported from `GitHub.Release.Check`): one-liner that owns env-var opt-out → `defaultConfig` → consumer `Config -> Config` modifier → `withUpdateCheck`, in that order, so the env-var kill switch wins over the modifier.
- **`versionOption`** in a new Cabal sublibrary `github-release-check:optparse` (`GitHub.Release.Check.OptParse`): an `optparse-applicative` `infoOption` printing `<exe> <semver>` and exiting `0`, taking the same `CliBanner` record as `withCli`. The sublibrary is the sole carrier of `optparse-applicative`.

Slice S1 carries one structural refactor: the engine definitions currently inside the umbrella `GitHub.Release.Check.hs` (`Config`, `defaultConfig`, `withUpdateCheck`, `runUpdateCheck`, `renderBanner`, and the private `runUnsafe`) move byte-for-byte into a new leaf `GitHub.Release.Check.Engine`. This breaks the otherwise-cyclic import between `Cli` (which needs `Config` / `defaultConfig` / `withUpdateCheck`) and the umbrella (which re-exports `module GitHub.Release.Check.Cli`). After the refactor the umbrella is pure re-export plumbing. All consumers continue to compile unchanged — every previously-exported identifier is still reachable through `import GitHub.Release.Check`.

The in-repo canary executable rewrites its `Main` to use both helpers (gains `--version`) and dogfoods the sublibrary wire-up on every CI build. The README is rewritten so the one-liner is the primary usage example, with the lower-level `defaultConfig` + `withUpdateCheck` API retained as the raw-control alternative.

Strictly additive at the public surface: every currently exported symbol survives unchanged.

## Technical Context

**Language/Version**: GHC 9.x (pinned via `flake.nix`), Cabal 3.4+
**Primary Dependencies (core lib, unchanged)**: aeson, base, bytestring, directory, filepath, http-client, http-client-tls, http-types, text, time
**New Dependency (sublibrary only)**: `optparse-applicative` (carried by `github-release-check:optparse`, NOT the core lib)
**Storage**: caller-supplied on-disk cache path (existing; not touched)
**Testing**: hspec + QuickCheck + hspec-discover, unit-tests suite under `test/`
**Target Platform**: any Haskell consumer (POSIX + Windows; same as today)
**Project Type**: Haskell library + canary executable
**Performance Goals**: N/A — sugar over an existing wrapper
**Constraints**: zero new transitive deps for consumers of just the core lib; existing public API surface preserved verbatim
**Scale/Scope**: ~150 LOC of new library code, ~50 LOC of new tests, canary rewrite, README rewrite

## Constitution Check

`.specify/memory/constitution.md` is an unfilled template (placeholder principles only). No gates to evaluate. The project-wide conventions that apply instead come from `/code/llm-settings/claude/rules/haskell.md` and the user's memory:

- 70-char fourmolu, leading commas/arrows
- Haddock on all exports, module headers required
- `-O0` everywhere in development
- `just`-mediated commands (build / unit / format-check / hlint / ci)
- `nix flake check` is the pre-push gate
- "Separate modules always" — new helpers go in new sibling modules + re-export
- "No bridges" — sugar wraps the real function directly, no shim types

All constraints can be satisfied with the planned design; no exceptions tracked.

## Project Structure

### Documentation (this feature)

```text
specs/001-withcli-helpers/
├── plan.md              # this file
├── research.md          # Phase 0: design decisions and rejected alternatives
├── data-model.md        # Phase 1: CliBanner entity + Config-composition pipeline
├── quickstart.md        # Phase 1: consumer integration walkthrough
├── contracts/
│   └── public-api.md    # Phase 1: pinned type signatures for both helpers
├── checklists/
│   └── requirements.md  # Spec quality checklist (already authored)
└── spec.md              # source of truth (already authored, clarifications resolved)
```

### Source Code (repository root)

```text
github-release-check.cabal       # ← +1 sublibrary section, +1 test-suite dep entry, canary dep updated
lib/                             # source root for the core `library` only
  GitHub/
    Release/
      Check.hs                   # ← becomes pure re-export plumbing (Cli + Decision + Engine + Fetcher)
      Check/
        Cli.hs                   # NEW — CliBanner type + composeCliConfig + withCli
        Engine.hs                # NEW — Config / defaultConfig / withUpdateCheck / runUpdateCheck / renderBanner (extracted byte-for-byte from the umbrella)
        Cache.hs                 # unchanged
        Decision.hs              # unchanged
        Fetcher.hs               # unchanged

lib-optparse/                    # source root for the `optparse` sublibrary ONLY (separate from `lib/` so GHC resolves Cli via the package dep, not the local source — avoids dragging core deps into the sublibrary and avoids needing PackageImports)
  GitHub/
    Release/
      Check/
        OptParse.hs              # NEW — versionOption
app/
  canary/
    Main.hs                      # ← rewritten to use withCli + versionOption
test/
  Spec.hs                        # unchanged (hspec-discover)
  GitHub/
    Release/
      Check/
        CacheSpec.hs             # unchanged
        DecisionSpec.hs          # unchanged
        CliSpec.hs               # NEW — env-var precedence + modifier composition
        OptParseSpec.hs          # NEW — versionOption execParserPure assertions
README.md                        # ← rewritten around the one-liner
gate.sh                          # extended to run the canary smoke (no-args + --version), then dropped in the final commit
```

**Structure Decision**: stay with the existing single-library layout. The new modules `GitHub.Release.Check.Cli` and `GitHub.Release.Check.Engine` are siblings of `Cache` / `Decision` / `Fetcher` and are re-exported from the umbrella `GitHub.Release.Check` for consumer ergonomics (one import). After the refactor the umbrella holds **no definitions** — it is pure re-export plumbing, which removes the otherwise-cyclic dependency between `Cli` and the umbrella and lets the project keep its "Separate modules always" rule (no `.hs-boot` workaround). The new sublibrary `github-release-check:optparse` adds one Cabal section and one new module `GitHub.Release.Check.OptParse`. No new top-level directories.

## Orchestrator vs Subagent Ownership (resolve-ticket addition)

| Asset | Owner |
|---|---|
| `spec.md`, `plan.md`, `tasks.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`, `checklists/` | **Orchestrator** (this skill chain) |
| `gate.sh` (add/extend/drop) | **Orchestrator** |
| README.md (final rewrite) | **Orchestrator** (mechanical docs edit, P3) |
| `lib/GitHub/Release/Check/Engine.hs` (new, extracted from umbrella), `lib/GitHub/Release/Check.hs` (becomes pure re-export plumbing), `lib/GitHub/Release/Check/Cli.hs` (new), `test/GitHub/Release/Check/CliSpec.hs` (new), cabal `exposed-modules` additions for `Cli` and `Engine` | **Subagent** (slice S1) |
| `lib/GitHub/Release/Check/OptParse.hs`, `test/GitHub/Release/Check/OptParseSpec.hs`, cabal sublibrary section, test-suite dep on sublib | **Subagent** (slice S2) |
| `app/canary/Main.hs` + canary cabal deps + gate.sh canary smoke | **Subagent** (slice S3) |
| `GitHub.Release.Check` re-export of `CliBanner` + `withCli` (one-line export-list edit) | Folded into slice S1 (subagent) |

## Vertical Commit Slices (resolve-ticket addition)

Each slice = one subagent run = one bisect-safe commit. Order matters because S2 builds on the public types declared in S1, S3 dogfoods both, and the README/finalization commits depend on the executable artifacts existing.

### S1 — Engine extraction + `withCli` + `CliBanner` in `GitHub.Release.Check.Cli`

**Subject**: `feat(cli): add CliBanner + withCli helper`
**Tasks** (enumerated in `tasks.md`): one structural refactor (extract `Engine`), one RED-GREEN pair for `withCli`, all folded into one bisect-safe commit.
**Files**: `lib/GitHub/Release/Check/Engine.hs` (new, contents moved from the umbrella byte-for-byte), `lib/GitHub/Release/Check.hs` (becomes pure re-export plumbing — `module Cli`, `module Decision`, `module Engine`, `module Fetcher`), `lib/GitHub/Release/Check/Cli.hs` (new — depends on `Engine`, not on the umbrella, so the import graph is acyclic), `test/GitHub/Release/Check/CliSpec.hs` (new), `github-release-check.cabal` (add both `Cli` and `Engine` to `exposed-modules`; add `CliSpec` to test-suite `other-modules`).
**Live-boundary diagnostic**: "What system boundary does this exercise that the unit suite cannot?" → **None**. Behavior = pure `Config` composition + `lookupEnv`. Unit suite (with `setEnv`/`unsetEnv` inside hspec) fully covers it. No smoke added in this slice.
**Why the refactor is in S1**: if `Cli.hs` imported `Config` / `defaultConfig` / `withUpdateCheck` from the umbrella while the umbrella re-exported `module Cli`, GHC would see a hard module-graph cycle. The escape hatches are (a) a `.hs-boot` file on the umbrella, or (b) extracting the engine into a leaf. (a) is a maintenance hazard (duplicated signatures) and goes against the project's "Separate modules always" rule; (b) cleanly removes the cycle and makes the umbrella's responsibility honest (pure re-export). We pick (b). The extraction is byte-for-byte, so the diff stays scoped and reviewable.

### S2 — `versionOption` in sublibrary `github-release-check:optparse`

**Subject**: `feat(optparse): add versionOption helper sublibrary`
**Files**: `lib/GitHub/Release/Check/OptParse.hs` (new, lives in the sublibrary), `test/GitHub/Release/Check/OptParseSpec.hs` (new), `github-release-check.cabal` (add `library optparse` sublibrary section, add `github-release-check:optparse` to unit-tests `build-depends`).
**Live-boundary diagnostic**: → **None**. `optparse-applicative`'s `execParserPure` is sufficient to exercise the `--version` path in-process (stdout capture + exit code). No smoke added in this slice.

### S3 — Canary dogfoods both helpers + gate.sh canary smoke

**Subject**: `feat(canary): wire withCli + versionOption (gains --version)`
**Files**: `app/canary/Main.hs` (rewritten), `github-release-check.cabal` (canary `build-depends` gains `github-release-check:optparse`), `gate.sh` (extended with canary smoke).
**Live-boundary diagnostic**: → **YES, new boundary**. This slice is the first place the actual built executable parses real argv, reads the real env, and exits with a real exit code. Unit tests cannot catch a regression in `Main.hs` wiring (wrong parser shape, missing `<**>`, env-var name typo). **gate.sh extended with:**
- `cabal run -O0 github-release-check-canary` (asserts exit 0 + single stdout line)
- `cabal run -O0 github-release-check-canary -- --version` (asserts exit 0 + first stdout line equals `github-release-check-canary <semver>`)

### S4 — README rewrite around the `withCli` one-liner

**Subject**: `docs(readme): rewrite Usage section around withCli one-liner`
**Owner**: orchestrator (pure docs, mechanical; no behavior change).
**Files**: `README.md`.
**Live-boundary diagnostic**: N/A (docs).

### S5 — Drop `gate.sh` (ready for review)

**Subject**: `chore: drop gate.sh (ready for review)`
**Owner**: orchestrator.
**Files**: `gate.sh` (deletion only).

## Proof Strategy (resolve-ticket addition)

| Slice | RED (failing test, observed before impl) | GREEN (passing test, after impl) |
|---|---|---|
| S1 | `CliSpec` is added importing `GitHub.Release.Check (CliBanner (..), composeCliConfig, withCli)`. **Compile fails**: module/type/function absent. Test cases assert: (a) env unset → `cfgDisabled = False` after composition; (b) env set → `cfgDisabled = True` regardless of modifier; (c) modifier mutates a non-`cfgDisabled` field and the change is visible in the composed `Config`; (d) order: `defaultConfig` → modifier → env-var override. To enable inspection, S1 also exports `composeCliConfig :: CliBanner -> (Config -> Config) -> IO Config` from `GitHub.Release.Check.Cli` (and re-exported); `withCli` is then defined as `composeCliConfig b f >>= \cfg -> withUpdateCheck cfg action`. The same commit extracts `Engine` from the umbrella so `Cli` can import `Config` / `defaultConfig` / `withUpdateCheck` directly from `Engine` (no cycle, no `.hs-boot`). | `Engine.hs` holds the extracted definitions; umbrella `Check.hs` becomes pure re-export plumbing; `Cli.hs` defines `CliBanner`, `composeCliConfig`, `withCli`; re-export added; tests pass. |
| S2 | `OptParseSpec` is added importing `GitHub.Release.Check.OptParse (versionOption)` and using `execParserPure`. **Compile fails** (sublibrary missing). Test cases (using `Options.Applicative.execParserPure` + the `ParserResult` API): (a) `--version` parser result is `Failure` carrying an `InfoMsg "github-release-check-canary <ver>"` (or equivalent), exit code resolution is 0 (`renderFailure` returns ExitSuccess); (b) absent `--version`, parser succeeds and yields the consumer's underlying parser value untouched. | Sublibrary section + `OptParse.hs` defines `versionOption` via `infoOption (renderVersion banner) (long "version" <> help "Show version")`; tests pass. |
| S3 | Smoke in `gate.sh` runs the freshly-built canary in both modes and `grep`s the first stdout line. **RED**: pre-rewrite canary fails the `--version` check (no flag yet). **GREEN**: rewrite canary using `withCli` + `versionOption`, smoke passes. The CliSpec/OptParseSpec from S1/S2 also guard the wiring at the unit level. | Canary Main rewritten; gate.sh smoke green. |
| S4 | N/A — docs only. The acceptance is "rendered README shows the `withCli` one-liner first" (visual check; orchestrator inspects the diff). | README rewritten. |
| S5 | N/A — `gate.sh` removed by deletion. Final gate.sh run happens at HEAD~1 immediately before the drop commit, so removal is safe. | `gate.sh` absent at HEAD. |

## Live-boundary Diagnostic Summary

The one boundary not covered by hspec is the **built executable's actual process behavior** (argv parsing, env read, exit code, stdout shape). That is covered by the canary smoke added to `gate.sh` in S3. No operator follow-up is deferred — the smoke runs inside the per-PR gate.

## `gate.sh` Evolution

| Commit | gate.sh state |
|---|---|
| `13fd0ae` (bootstrap) | initial: `git diff --check`, `just build`, `just unit`, `just format-check`, `just hlint` |
| After S3 | + `cabal run -O0 github-release-check-canary` (exit 0, one stdout line) + `cabal run -O0 github-release-check-canary -- --version` (exit 0, first line matches `github-release-check-canary <semver>`) |
| Final (S5) | **removed** (`chore: drop gate.sh (ready for review)`) |

## Open Risks / Trade-offs

- **`composeCliConfig` becomes part of the public surface** (so `CliSpec` can inspect the composed `Config` without exercising network I/O). This is a deliberate API choice — exposing the pure composition makes the helper testable and gives consumers an escape hatch if they want the assembled `Config` without entering `withUpdateCheck`. Captured as a design decision in `research.md`.
- **Sublibrary mechanics** in older Cabal: requires `cabal-version: 3.4` (already declared). Stack consumers occasionally need an explicit `library:` stanza in `stack.yaml`; we are not Stack-supported, so this is non-blocking — flagged in `research.md`.
- **Canary smoke depends on `cabal run`** rather than the built binary path. Acceptable: `gate.sh` already shells out via `nix develop`, so the cabal store is available. A future improvement would invoke the binary via `cabal list-bin`, but that's out of scope.

## Phase 0 → Phase 1 Gate

Constitution gate: pass (no real principles to violate). Spec gate: pass (no `[NEEDS CLARIFICATION]` markers left; clarifications session resolved both open questions on 2026-05-16). Plan ready for `/speckit.tasks` once the user reviews and authorises.

## Stop

Per user request, stop after Phase 1 artifacts. Do NOT proceed to `/speckit.tasks`. The orchestrator will commit `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, and `contracts/public-api.md`, push, and update the PR body to reflect the plan-stop.
