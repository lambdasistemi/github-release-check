# Feature Specification: `withCli` + `versionOption` helpers for CLI consumers

**Feature Branch**: `001-withcli-helpers`
**Created**: 2026-05-16
**Status**: Draft
**Input**: User description: "Expose `withCli` + `versionOption` helpers to remove boilerplate in consumer `Main` modules (issue #3)"

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Wire the upgrade banner with one line (Priority: P1)

A Haskell CLI author who already uses `github-release-check` wants to
add the upgrade-banner-on-exit behaviour to their executable's `Main`
module **with a single call**, instead of copy-pasting the 8-line
stanza (`lookupEnv` → `defaultConfig` → `Config { cfgDisabled = … }` →
`withUpdateCheck`) that today appears at every call site.

**Why this priority**: This is the load-bearing motivation in the
ticket. The same 8-line stanza is already duplicated in
`cardano-tx-tools` (`tx-validate`) and is about to be duplicated three
more times (`tx-diff`, `cardano-tx-generator`, `tx-sign`). Eliminating
that duplication is the only outcome that makes this feature worth
shipping.

**Independent Test**: An author can:

1. Build a tiny executable whose `Main.main` is `withCli banner action`
   for some user-supplied `action :: IO ()`.
2. Confirm `action` runs.
3. Set the opt-out environment variable named in `banner`, re-run, and
   confirm the upgrade check is skipped (no banner, no network
   activity) while `action` still runs.
4. Unset the env var and confirm the upgrade-check codepath is
   re-engaged on the next invocation.

The in-repo `github-release-check-canary` executable is the dogfood
site that exercises this story end-to-end on every build.

**Acceptance Scenarios**:

1. **Given** a CLI whose `Main.main` is rewritten as
   `main = withCli banner action`, **When** the executable is run with
   the opt-out env var **unset**, **Then** `action` executes and the
   library's existing update-check + banner pipeline runs after
   `action` returns (or throws), with no behavioural difference from
   the equivalent `do { cfg <- …; withUpdateCheck cfg action }` stanza.
2. **Given** the same CLI, **When** the executable is run with the
   opt-out env var **set** (to any value, including the empty string),
   **Then** `action` executes and the update check is a no-op (no
   network call, no banner).
3. **Given** the rewritten canary in this repo, **When** it is built
   and run, **Then** it behaves identically to the pre-rewrite canary
   (same stdout, same exit code, same banner-on-stale-cache behaviour)
   while its `Main` module is reduced to the one-liner shape.
4. **Given** an existing consumer that uses `defaultConfig` /
   `withUpdateCheck` directly, **When** this feature ships, **Then**
   that consumer still compiles and behaves identically without source
   changes (additive surface, no breaking renames).

---

### User Story 2 — Consistent `--version` flag across executables (Priority: P2)

A CLI author wants their executable's `--version` flag to print
`<exe> <semver>` and exit `0`, with **the same wording and exit
behaviour across every executable they ship**, without re-implementing
the optparse-applicative `infoOption` glue per executable or
re-passing the exe name and version value at each call site.

**Why this priority**: Same root cause as P1 (boilerplate +
inconsistency across executables). It is P2 because the upgrade-banner
story (P1) stands on its own — a consumer can adopt `withCli` today
without ever touching `--version`. `versionOption` is a complementary
helper for callers that already wire an optparse-applicative parser,
and it is gated to **not** force optparse-applicative on consumers who
do not use it.

**Independent Test**: An author can:

1. Plumb the helper into an optparse-applicative `Parser` (using
   whatever wiring this feature provides).
2. Run the resulting executable with `--version` and confirm the
   output is `<exe> <semver>` on a single line and exit code `0`.
3. Run the executable without `--version` and confirm the helper is
   inert (no interference with normal parsing).

**Acceptance Scenarios**:

1. **Given** a CLI whose parser includes the helper, **When** the user
   invokes `<exe> --version`, **Then** the executable prints
   `<exe> <semver>` (where `<exe>` and `<semver>` are taken from the
   same banner record used by `withCli`) and exits with status `0`.
2. **Given** the same CLI, **When** the user invokes any other
   command, **Then** the helper does not affect parsing, defaults, or
   help-text ordering of the other options.
3. **Given** a consumer that does **not** want the optparse-applicative
   integration, **When** the consumer depends only on the core library,
   **Then** their build does **not** transitively pull in
   `optparse-applicative`.

---

### User Story 3 — README + worked example show the new one-liner shape (Priority: P3)

A first-time reader of the project's `README.md` should learn the
`withCli` one-liner shape **first**, with the lower-level
`defaultConfig` / `withUpdateCheck` API documented as the
"raw-control" alternative. The README's "Usage" section should fit
the bundled helper, and the inlined consumer-side example should
demonstrate the ~6-line `Main` shape (matching the tx-validate call
site that already exists in `cardano-tx-tools`).

**Why this priority**: P3 because the helpers (P1, P2) can ship and
be adopted internally without README changes. But shipping the
helpers while leaving the README pointing at the old 8-line stanza
would mis-represent the library and force every new consumer to
re-discover the helper independently.

**Independent Test**: A reader who lands on the rendered `README.md`
can identify, within the first usage example, the `withCli` one-liner
shape and the location of the opt-out env-var convention.

**Acceptance Scenarios**:

1. **Given** the rewritten README, **When** a reader scans the
   "Usage" section, **Then** the first executable example uses
   `withCli` (not the 8-line stanza).
2. **Given** the rewritten README, **When** a reader looks for the
   raw-control API, **Then** `defaultConfig` and `withUpdateCheck`
   are still documented as the lower-level entry points.
3. **Given** the rewritten README, **When** a reader follows the
   downstream-consumer footnote, **Then** they reach the open
   `cardano-tx-tools#27` migration ticket.

---

### Edge Cases

- **Opt-out env var set to empty string**: The helper treats *any*
  presence of the variable (including `=""`) as "disabled", matching
  the existing `isJust <$> lookupEnv …` convention used in the
  current canary and in the tx-validate call site. Setting the var
  to `0` or `false` does **not** re-enable the check — only unsetting
  it does.
- **GitHub network failure / rate limit / DNS error**: The wrapped
  action's exit code is unchanged. The library is already silent on
  fetch failure; the helper does not change that contract.
- **`--version` invocation**: The optparse-applicative `infoOption`
  pattern short-circuits parsing and exits `0` before the wrapped
  action runs. As a consequence, the upgrade check does **not** run
  on a `--version` invocation. This is the same behaviour as
  `--help` and matches consumer expectations.
- **Consumer parser already defines `--version`**: The consumer is
  responsible for not double-defining the option. The helper provides
  a `Parser` modifier the consumer chooses where to insert.
- **Caller forgets to supply an opt-out env-var name**: The opt-out
  variable name is a mandatory field of the banner record; omitting
  it is a compile-time error.
- **Multiple executables share the same machine cache root**: Each
  executable already keys its cache directory on its own `cfgExeName`
  via `defaultConfig`; the helper preserves that key. Two
  executables with different `cliExe` values have independent caches.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose a single helper — referred to
  here as `withCli` — that accepts (a) a record bundling the
  consumer's repository slug, executable name, current `Version`, and
  opt-out env-var name, and (b) an `IO a` action, and runs the action
  with the existing `withUpdateCheck` semantics layered on top.
- **FR-002**: The helper MUST read the supplied opt-out env-var name
  via `lookupEnv` and set the underlying `cfgDisabled` flag to `True`
  iff the variable is present (matching the existing
  `isJust <$> lookupEnv …` convention).
- **FR-003**: The helper MUST build the underlying `Config` via the
  existing `defaultConfig`, so that any future change to defaults
  flows through both the raw and the bundled API.
- **FR-004**: The library MUST continue to export `withUpdateCheck`,
  `runUpdateCheck`, `defaultConfig`, `Config (..)`, `RepoSlug`,
  `renderBanner`, and the `Decision` / `Fetcher` re-exports
  unchanged. No existing import on a current consumer breaks.
- **FR-005**: The library MUST expose an optparse-applicative
  `--version` helper — referred to here as `versionOption` — that,
  when plumbed into a consumer parser, prints `<exe> <semver>` on a
  single line and exits with status `0`, using the same banner record
  as `withCli` so the exe name and version are sourced from one
  place.
  [NEEDS CLARIFICATION: Packaging of `versionOption` — the issue
  explicitly leaves the choice open between (a) a Cabal sublibrary
  `github-release-check:optparse` carrying the `optparse-applicative`
  dependency, and (b) a polymorphic API that takes the consumer's
  parser-applicative as an argument so no new sublibrary is needed.
  This decision affects what the consumer adds to their
  `build-depends` and how they import the helper.]
- **FR-006**: The core library (the default `github-release-check`
  component a consumer pulls in) MUST NOT add `optparse-applicative`
  to its `build-depends`. A consumer that only uses `withCli` MUST
  NOT transitively pull `optparse-applicative` into their build plan.
- **FR-007**: The banner record (the record passed to `withCli` and
  `versionOption`) MUST keep the opt-out env-var name as a required,
  caller-supplied field. The library MUST NOT bake a default name
  into the type.
- **FR-008**: The in-repo canary executable
  (`github-release-check-canary`) MUST be rewritten to use both
  `withCli` and `versionOption` (it gains a `--version` flag), so the
  feature is dogfooded end-to-end on every CI build.
- **FR-009**: The project `README.md` MUST be rewritten so the
  primary "Usage" example shows the `withCli` one-liner, with the
  existing `defaultConfig` / `withUpdateCheck` usage retained as a
  documented lower-level alternative.
- **FR-010**: The rewritten README MUST include an inlined
  ~6-line consumer-side `Main` example demonstrating the one-liner
  shape, with a footnote pointing at the downstream
  `cardano-tx-tools#27` migration ticket as a real call site.

### Key Entities

- **Banner record** (working name `CliBanner`): bundles the four
  values every consumer already supplies — repository slug,
  executable name, current `Version`, opt-out env-var name. It is the
  single argument both `withCli` and `versionOption` take, so the
  consumer defines it once per executable and re-uses it across both
  helpers.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new consumer wires the upgrade-banner-on-exit
  behaviour into a fresh executable in **one** statement
  (`main = withCli banner action`), down from the current ~8-line
  stanza. Measured by the diff size of a representative consumer
  migration (the in-repo canary rewrite is the reference point).
- **SC-002**: Existing consumers of `defaultConfig` /
  `withUpdateCheck` upgrade to the new library version with **zero
  source changes** required, including those that do **not** adopt
  the new helpers. Measured by the canary's pre-feature `Main.hs`
  continuing to compile against the post-feature library if pasted
  in unchanged.
- **SC-003**: A consumer that uses only `withCli` (and not
  `versionOption`) does **not** transitively depend on
  `optparse-applicative`. Measured by inspecting the consumer's
  resolved build plan.
- **SC-004**: The in-repo canary uses both helpers and exits with
  status `0` on a normal invocation and on `--version`. Measured by
  the canary smoke step running in the per-PR gate.

## Assumptions

- The canary executable becomes the in-repo proof site for both
  helpers, including `--version`. No other in-repo consumer is
  introduced by this feature.
- The opt-out env-var name remains caller-supplied (per the issue
  constraint). Documentation explains the recommended naming
  convention (`<EXE>_NO_UPDATE_CHECK`, upper-snake-cased exe name)
  but the library does not enforce or default it.
- The wrapped action's exit code semantics, exception handling, and
  silent-on-fetch-failure contract are preserved verbatim by the
  helper — it is sugar over `withUpdateCheck`, not a redesign.
- Downstream consumer migration (`cardano-tx-tools`'s four
  executables) is out of scope of this PR. It is tracked separately
  under `cardano-tx-tools#27` and only referenced from the README as
  a worked example.
- This feature is **strictly additive** to the public API surface.
  No rename, removal, or signature change of an existing exported
  identifier is in scope.
