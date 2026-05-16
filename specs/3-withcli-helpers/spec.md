# Spec — `withCli` + `versionOption` helpers (issue #3)

- **Issue:** [lambdasistemi/github-release-check#3][issue]
- **Downstream driver:** [lambdasistemi/cardano-tx-tools#27][downstream]
  (4 executables about to repeat the same 8-line stanza)
- **Status:** draft, awaiting orchestrator-side review at the `specs`
  phase stop

[issue]: https://github.com/lambdasistemi/github-release-check/issues/3
[downstream]: https://github.com/lambdasistemi/cardano-tx-tools/issues/27

## Problem

Every CLI that wants the update banner today repeats the same glue
(see `app/canary/Main.hs` for the in-repo example, lines 42–53):

```haskell
disabled <- isJust <$> lookupEnv "CANARY_NO_UPDATE_CHECK"
cfg      <- defaultConfig (RepoSlug "owner" "repo") "exe" version
withUpdateCheck cfg{cfgDisabled = disabled} $ do
    ...
```

Four `cardano-tx-tools` executables (`tx-validate`, `tx-diff`,
`cardano-tx-generator`, `tx-sign`) are about to grow the same stanza
([#27][downstream]; `tx-validate` already has it in [#20][pr20]). With
four copies, the env-var naming convention should be locked in code
rather than re-invented per call site.

[pr20]: https://github.com/lambdasistemi/cardano-tx-tools/pull/20

## P1 — Operator story (the paramount user story)

> As the maintainer of a small Haskell CLI, I want to add an update
> banner with **one binding (`CliBanner`) and one wrap (`withCli`)**,
> so my `Main.hs` does not carry 8 lines of identical opt-out + config
> + wrap boilerplate, and so the opt-out env-var name follows the
> documented project convention.

### Acceptance scenarios (P1)

1. **Given** a downstream `Main.hs` that defines a
   `CliBanner { cliRepo, cliExe, cliVersion, cliOptOutEnvVar }`,
   **when** the maintainer writes `main = withCli banner realMain`,
   **then** at runtime:
   - If `cliOptOutEnvVar` is set (any value), the wrapped action runs
     and the update check is a no-op.
   - Otherwise, the wrapped action runs and on exit the same banner
     logic exposed by `withUpdateCheck` fires, using `defaultConfig`
     seeded from `cliRepo`, `cliExe`, `cliVersion`.
   - Exceptions thrown by the wrapped action propagate unchanged; the
     check runs in `finally` and never alters the action's exit code.
2. **Given** an existing caller that today uses
   `defaultConfig` + `withUpdateCheck` directly, **when** the new
   release ships, **then** that code compiles unchanged. `withCli` is
   strictly additive on top of the existing surface.
3. **Given** the canary executable (`app/canary/Main.hs`) which is the
   in-repo dogfood site, **when** the new helpers land, **then** the
   canary is rewritten around `withCli` and remains ≤ 4 functional
   lines of glue inside `main`. The canary's existing opt-out env-var
   name (`GITHUB_RELEASE_CHECK_CANARY_NO_UPDATE_CHECK`) is preserved.

## P2 — Consistent `--version` flag

> As the maintainer, I want an `optparse-applicative`-friendly
> `--version` flag that prints `<exe> <semver>` and exits 0, **without
> adding `optparse-applicative` to the core library's dependency
> closure**.

### Acceptance scenarios (P2)

1. **Given** a `CliBanner`, **when** the consumer composes its
   `optparse-applicative` parser with `versionOption banner`, **then**
   `<exe> --version` prints exactly `<cliExe> <showVersion cliVersion>`
   on stdout and exits 0, and the rest of the parser is unaffected.
2. **Given** a consumer that does **not** want a `--version` flag,
   **when** they depend on the core library only, **then** their build
   does **not** pull in `optparse-applicative` transitively.

## Design decision — sublibrary, not polymorphic

Selected at the phase interview on 2026-05-16:

- `versionOption` lives in a Cabal **internal sublibrary**:
  `github-release-check:optparse`.
- The sublibrary `build-depends` on `optparse-applicative`. The main
  library does **not**.
- Public module name: `GitHub.Release.Check.Optparse` (exposed from
  the sublibrary; users depend on it via
  `build-depends: github-release-check:optparse`).
- Rejected alternative: polymorphic / typeclass-based helper in core.
  Rationale: a sublibrary keeps the core dep list minimal and the
  optparse API ergonomic (real `Parser (a -> a)`, not a polymorphic
  shadow). The strawman in the issue chose this same shape; we lock
  it.

## Public surface (target)

In the **core library** (`GitHub.Release.Check` or a new
`GitHub.Release.Check.Cli` module re-exported from `GitHub.Release.Check`):

```haskell
data CliBanner = CliBanner
    { cliRepo         :: !RepoSlug
    , cliExe          :: !Text
    , cliVersion      :: !Version
    , cliOptOutEnvVar :: !String
    }

withCli :: CliBanner -> IO a -> IO a
```

In the **`github-release-check:optparse` sublibrary**
(`GitHub.Release.Check.Optparse`):

```haskell
versionOption :: CliBanner -> Parser (a -> a)
```

`Config (..)`, `defaultConfig`, `withUpdateCheck`, `runUpdateCheck`,
`renderBanner`, `RepoSlug (..)`, and everything else currently
exported remain exported unchanged. `withCli` is layered **on top of**
`defaultConfig` + `withUpdateCheck`; it does not duplicate their
logic.

## Out of scope (exclusions)

- **No default env-var name.** `cliOptOutEnvVar` stays caller-supplied;
  the convention is documented in the README but not baked into the
  type. (Constraint from the issue.)
- **No mandatory `optparse-applicative` dependency in core.**
  Consumers that only want `withCli` get zero new transitive deps.
- **No removal or rename of `withUpdateCheck` / `defaultConfig` /
  `Config`.** The new helpers are additive; old callers compile
  unchanged.
- **No change to fetch / cache / decision semantics.** This ticket is
  pure boilerplate compression at the API edge.
- **No downstream `cardano-tx-tools` migration.** That belongs to
  [#27][downstream]; this PR ships the helpers + canary rewrite + docs
  only.
- **No new CLI behavior on the canary** beyond the rewrite. The canary
  continues to print one line and exit 0, banner-on-exit.

## Measurable outcomes

- Canary `main` is at most 4 functional lines of glue around
  `withCli`, plus the `CliBanner` binding.
- README "Usage" section opens with the `withCli` one-liner; the raw
  `defaultConfig` + `withUpdateCheck` recipe stays as an "advanced"
  subsection.
- Cabal: core library `build-depends` is unchanged (no
  `optparse-applicative` added). New sublibrary
  `github-release-check:optparse` is exposed and used at most by the
  test-suite and (optionally) by the canary.
- `cabal check` passes (Hackage-ready, per project rule).
- `nix flake check` is green.
- The four `cardano-tx-tools` executables can collapse their stanzas
  to ≤ 4 lines once they bump the pin (verified by quoting the future
  consumer shape in the README — actual migration is out of scope).

## Open questions for the user (specs stop)

These are recorded here, not yet decided. The plan phase needs an
answer before tasks/code:

1. **Module location of `withCli`.** Two reasonable choices:
   - put `CliBanner` and `withCli` in `GitHub.Release.Check` directly
     (one fewer module, smaller surface);
   - put them in `GitHub.Release.Check.Cli` and re-export from
     `GitHub.Release.Check` (cleaner separation, more files).

   Recommendation: **new `GitHub.Release.Check.Cli` module,
   re-exported from `GitHub.Release.Check`**. Rationale: keeps the
   "raw" `Check` module focused on the update-check engine and lets
   the optparse sublibrary import `Cli` without dragging the engine
   re-exports.

2. **Should the canary depend on `github-release-check:optparse` to
   get `--version`?** The canary currently has no argument parser at
   all (just `main = ...`). Adding `--version` is the natural dogfood
   for `versionOption`, but it grows the canary dep closure to
   include `optparse-applicative`.

   Recommendation: **yes, dogfood it.** The canary's whole job is
   integration coverage; not exercising `versionOption` leaves the
   new sublibrary uncovered. Cost is one extra dep on one tiny
   executable, not on the library.

3. **Banner sink for the consumer-side worked example in the README.**
   The issue says "linking from cardano-tx-tools' tx-validate
   demonstrates the one-liner shape." Until that downstream change
   actually lands, do we link to the future call site, or inline the
   example?

   Recommendation: **inline a 6-line example in the README** showing
   the target `tx-validate` `Main.hs` shape, and add a footnote
   pointing at [#27][downstream]. Replace with a permalink once the
   downstream PR is merged.

## Gate sketch (for the plan phase)

The plan will turn these into `llm/reviews/local-3-withcli-helpers/gate.sh`:

```bash
nix develop --quiet -c just format-check
nix develop --quiet -c just hlint
nix develop --quiet -c just build
nix develop --quiet -c just unit
nix develop --quiet -c cabal check
nix flake check --no-eval-cache
nix run .#canary           # dogfood: ensure rewritten canary still prints
```

A unit test for `withCli` opt-out behavior (env-var set ⇒ no fetch,
no banner) is the natural RED for the P1 slice. A unit test asserting
`versionOption` produces `<exe> <semver>\n` on stdout and exits 0 via
`execParserPure` is the RED for the P2 slice.
