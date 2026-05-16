---

description: "Tasks for feature 001-withcli-helpers (issue #3)"
---

# Tasks: `withCli` + `versionOption` helpers

**Input**: Design documents in `specs/001-withcli-helpers/`
**Prerequisites**: [`spec.md`](./spec.md), [`plan.md`](./plan.md), [`research.md`](./research.md), [`data-model.md`](./data-model.md), [`contracts/public-api.md`](./contracts/public-api.md), [`quickstart.md`](./quickstart.md)

**Tests**: REQUIRED (TDD — RED test first per behavior-changing slice).

**Organization**: Tasks are grouped by [vertical commit slice](./plan.md#vertical-commit-slices-resolve-ticket-addition) (S1–S5). Each slice corresponds to **one subagent run** producing **one bisect-safe commit**. RED + GREEN tasks within a slice **fold into the same commit** — they are not separate commits.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with other `[P]` tasks. Most tasks here are intra-slice and not parallel; only orchestrator chores between slices use `[P]`.
- **[Story]**: Which user story this task belongs to (US1 = withCli one-liner, US2 = versionOption, US3 = README rewrite).
- Each task names exact file paths.

After a slice ships, the orchestrator marks every task in the slice `[X] T### (commit: <short-sha>)` and amends the slice commit so the `tasks.md` change rides with the code (per resolve-ticket two-sided link rule).

---

## Phase 1: Setup

No setup tasks. The repo already has `flake.nix`, `justfile`, `github-release-check.cabal`, fourmolu config, and `gate.sh`. The Spec Kit scaffold (`.specify/`, `specs/001-withcli-helpers/`) is already committed.

## Phase 2: Foundational

No foundational tasks. Each slice below is fully self-contained — its cabal/source/test/cabal-dep edits all live in the slice's single commit so the slice is bisect-safe by construction.

---

## Phase 3: Slice S1 — `withCli` + `CliBanner` in `GitHub.Release.Check.Cli` (US1, P1) 🎯 MVP

**Goal**: One-line `withCli` replacing the 8-line stanza; supports a `Config -> Config` modifier; env-var kill switch wins over the modifier.

**Independent Test**: After this slice ships, a consumer can write `main = withCli banner id action` (or with a non-`id` modifier) and the upgrade-banner-on-exit behaviour works identically to the current `do { disabled <- …; cfg <- defaultConfig …; withUpdateCheck cfg{ cfgDisabled = disabled } action }` stanza.

**Public-API contract**: [`contracts/public-api.md` § Module `GitHub.Release.Check.Cli`](./contracts/public-api.md#module-githubreleasecheckcli-new-in-core-library) and § Module `GitHub.Release.Check` (additive re-export).

**Composition truth table** (consumer-modifier vs env-var precedence): [`data-model.md` § Composition Pipeline](./data-model.md#composition-pipeline--composecliconfig).

### Tasks for slice S1

- [ ] T001 [US1] RED — Add `test/GitHub/Release/Check/CliSpec.hs` (new) with hspec test cases that **fail to compile** initially (import `GitHub.Release.Check (CliBanner (..), composeCliConfig, withCli)` which do not yet exist). Tests must assert the four rows of the [`composeCliConfig` truth table](./data-model.md#composition-pipeline--composecliconfig), plus the modifier-applies-to-non-`cfgDisabled` fields case. Use `System.Environment.setEnv` / `unsetEnv` inside hspec `around_` to control the opt-out env var per case. Also add `GitHub.Release.Check.CliSpec` to the unit-tests `other-modules` in `github-release-check.cabal`. Observe RED: `just build` reports module/symbol not found.
- [ ] T002 [US1] GREEN — Add `lib/GitHub/Release/Check/Cli.hs` (new) defining `CliBanner (..)`, `composeCliConfig :: CliBanner -> (Config -> Config) -> IO Config`, and `withCli :: CliBanner -> (Config -> Config) -> IO a -> IO a` exactly as per [`contracts/public-api.md`](./contracts/public-api.md#module-githubreleasecheckcli-new-in-core-library). Add `GitHub.Release.Check.Cli` to the library `exposed-modules` in `github-release-check.cabal`. Add a re-export `module GitHub.Release.Check.Cli` to `lib/GitHub/Release/Check.hs`'s export list (additive only; no other identifier touched). Module header + Haddock on every export. Implementation literally: `defaultConfig` → apply consumer `f` → if env var present, override `cfgDisabled = True`. Run `just unit` and confirm CliSpec passes.
- [ ] T003 [US1] FOLD — T001 and T002 MUST be a single bisect-safe commit (resolve-ticket rule: one slice = one commit). The subagent stages all RED + GREEN files together and commits once.

**Checkpoint**: After slice S1 ships, P1's load-bearing acceptance scenarios (#1–#6) hold; no other slice depends on S1's internals beyond the public `CliBanner` re-export.

### Subagent brief — S1

```text
Task: T001, T002, T003 (slice S1)

Context:
- You are not alone in the codebase. Do not revert edits made by others.
- Make exactly ONE commit. Do not push.
- This commit must be bisect-safe and vertical: building the commit at
  HEAD must succeed; tests required by ./gate.sh must pass; no WIP,
  draft, tmp, fixup, or squash commits.
- Commit subject must match Conventional Commits:
  `feat(cli): add CliBanner + withCli helper`
- The commit body MUST include the trailer:
  `Tasks: T001, T002, T003`
- Sign the commit with GPG (`git commit -S`).

Owned files:
- lib/GitHub/Release/Check/Cli.hs (new)
- lib/GitHub/Release/Check.hs (export list only — add one re-export line)
- test/GitHub/Release/Check/CliSpec.hs (new)
- github-release-check.cabal (add Cli to library exposed-modules; add CliSpec to test-suite other-modules)

Forbidden scope:
- specs/ (orchestrator owns)
- gate.sh (orchestrator owns; subagent S3 will be authorized to extend it later)
- README.md
- app/canary/Main.hs (slice S3 territory)
- New sublibrary section in the cabal file (slice S2 territory)
- Any change to existing identifiers in lib/GitHub/Release/Check{,/Cache,/Decision,/Fetcher}.hs other than the one re-export line in lib/GitHub/Release/Check.hs
- PR / issue metadata

Required orchestrator analysis already applied (do NOT re-derive):
- Public-API contract: specs/001-withcli-helpers/contracts/public-api.md § "Module GitHub.Release.Check.Cli" and § "Module GitHub.Release.Check".
- CliBanner field types: specs/001-withcli-helpers/data-model.md § "Entity — CliBanner".
- Composition order: defaultConfig → consumer modifier (Config -> Config) → if env-var present, force cfgDisabled = True. The env-var kill switch wins (specs/001-withcli-helpers/data-model.md § truth table, plus spec.md FR-002 + FR-003 + P1 acceptance #6).
- composeCliConfig MUST be exported alongside withCli (research.md Decision 4 — needed for test inspection without faking the fetcher).
- Module placement: new sibling module GitHub.Release.Check.Cli + re-export from GitHub.Release.Check. Do NOT fold into the umbrella module (project rule "Separate modules always").
- Haddock: every export gets a haddock; module gets a header (project convention).
- Fourmolu 70-char line limit, leading commas/arrows.
- Use GHC2021 + the project's default-extensions block (already inherited via `import: warnings` and the common stanza).

RED proof (write first, observe failing):
- Add test/GitHub/Release/Check/CliSpec.hs importing the symbols that do not yet exist. Initially run `just build` and observe the build/test FAIL with "Variable not in scope" or similar.
- The CliSpec must cover the four-row composition truth table from data-model.md:
  (a) env unset, modifier id → cfgDisabled = False after composeCliConfig
  (b) env unset, modifier sets cfgDisabled = True → cfgDisabled = True
  (c) env SET, modifier id → cfgDisabled = True
  (d) env SET, modifier sets cfgDisabled = False → cfgDisabled = True (env wins — this is the kill-switch invariant from P1 acceptance #6)
  PLUS:
  (e) modifier override of a non-cfgDisabled field (e.g. cfgCheckInterval) survives composition unchanged
- Use hspec `around_` with `setEnv` / `unsetEnv` from System.Environment to control the env var per case. The env-var name in each test can be unique per spec (e.g. "WITHCLI_TEST_OPT_OUT_<n>") to avoid leakage.
- Stage these test edits + the cabal `other-modules` line in the SAME commit as the implementation; observe RED locally before staging the implementation files.

GREEN proof (must pass after implementation):
- nix develop --quiet -c just unit
- ./gate.sh
- Both must exit 0. The hspec output must show CliSpec cases all passing.

Commit subject (use this exact title):
- feat(cli): add CliBanner + withCli helper

Report back (exactly these fields):
- Files changed (paths only).
- RED evidence: paste the failing `just build` (or `just unit`) output BEFORE the implementation files were added.
- GREEN evidence: paste the tail of `just unit` output AFTER the implementation, showing CliSpec passing, plus the tail of `./gate.sh`.
- Commit short-sha and the Tasks: trailer line from the commit body.
- Residual risks or follow-ups, if any.
```

---

## Phase 4: Slice S2 — `versionOption` in sublibrary `github-release-check:optparse` (US2, P2)

**Goal**: A `--version` `infoOption` printing `<exe> <semver>` and exiting 0, defined in a sublibrary so the core library stays free of `optparse-applicative`.

**Independent Test**: After this slice ships, a consumer can add `github-release-check:optparse` to their `build-depends` and write `myParser <**> versionOption banner`; the resulting executable's `--version` flag prints the expected line and exits 0.

**Public-API contract**: [`contracts/public-api.md` § Module `GitHub.Release.Check.OptParse`](./contracts/public-api.md#module-githubreleasecheckoptparse-new-in-sublibrary-github-release-checkoptparse) and § Cabal manifest deltas.

### Tasks for slice S2

- [ ] T004 [US2] RED — Add `test/GitHub/Release/Check/OptParseSpec.hs` (new) with hspec cases that **fail to compile** initially (import `GitHub.Release.Check.OptParse (versionOption)` which does not yet exist). Tests use `Options.Applicative.execParserPure` per [`research.md` Decision 8](./research.md#decision-8--test-approach-for-versionoption): (a) parsing `["--version"]` returns a `Failure` whose rendered output is exactly `"<cliExe banner> <showVersion (cliVersion banner)>\n"` and whose resolved exit code is `ExitSuccess`; (b) parsing `[]` against a baseline parser succeeds, leaves the underlying value untouched. Add `GitHub.Release.Check.OptParseSpec` to test-suite `other-modules`, add `github-release-check:optparse` and `optparse-applicative` to the test-suite `build-depends` (per [`contracts/public-api.md` § Cabal manifest deltas](./contracts/public-api.md#cabal-manifest-deltas)). Observe RED.
- [ ] T005 [US2] GREEN — Add the `library optparse` section to `github-release-check.cabal` exactly as specified in [`contracts/public-api.md` § Cabal manifest deltas](./contracts/public-api.md#cabal-manifest-deltas). Add `lib/GitHub/Release/Check/OptParse.hs` (new, in `hs-source-dirs: lib` per the sublibrary section) defining `versionOption :: CliBanner -> Parser (a -> a)` and a private `renderVersion :: CliBanner -> String`, exactly matching the contract. Module header + Haddock on `versionOption`. Run `just unit` and confirm OptParseSpec passes.
- [ ] T006 [US2] FOLD — T004 and T005 MUST be a single bisect-safe commit.

**Checkpoint**: After slice S2 ships, P2 acceptance scenarios (#1, #2, #3) hold. The core library's `build-depends` still does NOT include `optparse-applicative`.

### Subagent brief — S2

```text
Task: T004, T005, T006 (slice S2)

Context:
- You are not alone in the codebase. Do not revert edits made by others.
- Make exactly ONE commit. Do not push.
- This commit must be bisect-safe and vertical.
- Commit subject must match Conventional Commits:
  `feat(optparse): add versionOption helper sublibrary`
- Commit body MUST include trailer: `Tasks: T004, T005, T006`
- Sign with GPG (`git commit -S`).
- Slice S1 is ASSUMED ALREADY MERGED into the branch (CliBanner is available via `import GitHub.Release.Check.Cli (CliBanner (..))`).

Owned files:
- lib/GitHub/Release/Check/OptParse.hs (new, lives in sublibrary)
- test/GitHub/Release/Check/OptParseSpec.hs (new)
- github-release-check.cabal (add `library optparse` section; add sublibrary + optparse-applicative to test-suite build-depends; add OptParseSpec to test-suite other-modules)

Forbidden scope:
- specs/
- gate.sh (S3 territory)
- README.md
- app/canary/Main.hs (S3 territory)
- lib/GitHub/Release/Check/Cli.hs and any other already-merged S1 file
- Adding optparse-applicative to the core `library` build-depends — that is forbidden (FR-006). Only the sublibrary, test-suite, and (later, in S3) the canary depend on it.

Required orchestrator analysis already applied (do NOT re-derive):
- Public-API contract: specs/001-withcli-helpers/contracts/public-api.md § "Module GitHub.Release.Check.OptParse" — `versionOption :: CliBanner -> Parser (a -> a)`.
- Cabal manifest delta: same file § "Cabal manifest deltas" — the new `library optparse` section and the test-suite dep additions. Copy the structure as specified; do not invent new fields.
- Implementation shape: `versionOption b = infoOption (renderVersion b) (long "version" <> help "Show the version and exit")`. `renderVersion b = T.unpack (cliExe b) <> " " <> showVersion (cliVersion b)`.
- Test approach: `execParserPure defaultPrefs (info (pure () <**> versionOption banner) idm) ["--version"]` → match `Failure` constructor; use `renderFailure` to get the printed string and `ExitCode`. See research.md Decision 8.
- `renderVersion` stays private to the OptParse module (not exported).

RED proof (write first):
- Stage OptParseSpec.hs importing `GitHub.Release.Check.OptParse (versionOption)`. Add it to test-suite other-modules. Run `just build` and observe the test compilation FAILS because the sublibrary doesn't exist yet.
- The two test cases:
  (a) `--version` parser failure whose rendered first line is exactly `"<cliExe banner> <showVersion (cliVersion banner)>"`, and `renderFailure` reports `ExitSuccess`.
  (b) `[]` parser success returns the underlying value unchanged (use `pure 42 <**> versionOption banner` and assert the result is 42).

GREEN proof:
- nix develop --quiet -c just unit
- ./gate.sh
- The sublibrary builds; OptParseSpec passes; core library's build-depends still excludes optparse-applicative (the build log should NOT pull optparse-applicative into the core library compile step).

Commit subject:
- feat(optparse): add versionOption helper sublibrary

Report back:
- Files changed.
- RED evidence (failing build/test output BEFORE implementation).
- GREEN evidence (passing just unit + ./gate.sh tail).
- Commit short-sha + Tasks: trailer.
- Confirm in writing that lib/GitHub/Release/Check.hs's build-depends was NOT modified.
```

---

## Phase 5: Slice S3 — Canary dogfoods both helpers + `gate.sh` canary smoke (US1 + US2, dogfood site)

**Goal**: The in-repo `github-release-check-canary` is rewritten to use `withCli` + `versionOption`, gaining a `--version` flag. `gate.sh` is extended with a canary smoke (no-args + `--version`) so the live-boundary diagnostic (real argv parsing, real env read, real exit code) is covered on every PR run.

**Independent Test**: `cabal run github-release-check-canary` exits 0 with one stdout line; `cabal run github-release-check-canary -- --version` prints `github-release-check-canary <semver>` and exits 0; `GITHUB_RELEASE_CHECK_CANARY_NO_UPDATE_CHECK=1 cabal run github-release-check-canary` exits 0 without contacting the network.

**Public-API contract**: [`contracts/public-api.md` § Cabal manifest deltas](./contracts/public-api.md#cabal-manifest-deltas) — canary `build-depends` gains `github-release-check:optparse` and `optparse-applicative`.

**Why gate.sh is editable in this slice**: extending `gate.sh` *before* the canary rewrite would break the gate on the pre-rewrite canary; extending it *after* would mean an intermediate commit where the new gate.sh exists but the canary doesn't satisfy it. Both violate bisect-safety. The only bisect-safe option is to bundle the gate.sh extension and the canary rewrite in the same commit — so for S3 the subagent is explicitly authorized to edit `gate.sh`.

### Tasks for slice S3

- [ ] T007 [US1] [US2] RED — Extend `gate.sh` with the two canary smoke checks (see [`plan.md` § `gate.sh` Evolution](./plan.md#gatesh-evolution)): `cabal run -O0 github-release-check-canary` (assert exit 0, exactly one stdout line) and `cabal run -O0 github-release-check-canary -- --version` (assert exit 0, first stdout line equals `github-release-check-canary <semver>`). Run `./gate.sh`; it MUST fail on the `--version` step because the pre-rewrite canary does not yet support `--version`. This is the RED.
- [ ] T008 [US1] [US2] GREEN — Rewrite `app/canary/Main.hs` to use `withCli banner id` + `versionOption banner` as shown in [`research.md` Decision 6](./research.md#decision-6--canary---version-wiring). Update `github-release-check.cabal`'s `executable github-release-check-canary` `build-depends` to add `github-release-check:optparse` and `optparse-applicative` (per the canary delta in [`contracts/public-api.md` § Cabal manifest deltas](./contracts/public-api.md#cabal-manifest-deltas)). Preserve the canary's stdout shape (one line: `<exe> <ver> — library wired against <owner>/<repo>`). Module header + Haddock unchanged-or-updated. Run `./gate.sh`; it must now pass green including the canary smoke.
- [ ] T009 [US1] [US2] FOLD — T007 and T008 MUST be a single bisect-safe commit. The gate.sh edit cannot ship independently.

**Checkpoint**: After slice S3 ships, FR-008 holds; SC-004 holds; the live-boundary diagnostic for the executable surface is permanently covered by `gate.sh`.

### Subagent brief — S3

```text
Task: T007, T008, T009 (slice S3)

Context:
- You are not alone in the codebase. Do not revert edits made by others.
- Slices S1 and S2 are ASSUMED ALREADY MERGED. CliBanner is in
  GitHub.Release.Check; versionOption is in GitHub.Release.Check.OptParse
  (sublibrary github-release-check:optparse).
- Make exactly ONE commit. Do not push.
- Bisect-safe and vertical.
- Commit subject:
  `feat(canary): wire withCli + versionOption (gains --version)`
- Commit body MUST include trailer: `Tasks: T007, T008, T009`
- Sign with GPG.

Owned files:
- app/canary/Main.hs (rewrite)
- github-release-check.cabal (canary build-depends only — add github-release-check:optparse and optparse-applicative)
- gate.sh — EXPLICITLY AUTHORIZED for this slice only, to add the canary smoke. Do not touch any other gate.sh line.

Forbidden scope:
- specs/
- README.md (S4 territory — orchestrator)
- lib/, test/, .specify/
- Any other gate.sh edit beyond appending the two canary smoke lines

Required orchestrator analysis (do NOT re-derive):
- Canary Main.hs shape: research.md Decision 6. The banner record uses cliRepo = RepoSlug "lambdasistemi" "github-release-check", cliExe = "github-release-check-canary", cliVersion = version, cliOptOutEnvVar = "GITHUB_RELEASE_CHECK_CANARY_NO_UPDATE_CHECK". Modifier = id. Use `execParser (info (pure () <**> versionOption banner <**> helper) idm)` BEFORE entering withCli (so --version short-circuits without running the update check, matching the documented edge case).
- Preserve the canary's existing stdout line: `<exeName> <showVersion version> — library wired against <owner>/<repo>`.
- gate.sh smoke lines (append to existing gate.sh, before any final cleanup):
    nix develop --quiet -c cabal run -O0 github-release-check-canary > /tmp/canary.out
    [ "$(wc -l < /tmp/canary.out)" = "1" ] || { echo "canary smoke: expected 1 stdout line"; cat /tmp/canary.out; exit 1; }
    nix develop --quiet -c cabal run -O0 github-release-check-canary -- --version > /tmp/canary-version.out
    head -1 /tmp/canary-version.out | grep -qE "^github-release-check-canary [0-9]+(\.[0-9]+)*$" || { echo "canary --version line mismatch"; cat /tmp/canary-version.out; exit 1; }
  (You may inline or adapt this snippet. The exact assertion shape matters, not the exact shell flavour.)
- Cabal delta for canary: contracts/public-api.md § Cabal manifest deltas — the executable github-release-check-canary section adds `github-release-check:optparse` and `optparse-applicative >=0.18 && <0.20` to its build-depends.

RED proof:
- Apply ONLY the gate.sh extension first; run `./gate.sh`. It must FAIL on the `--version` smoke (the unmodified canary errors out on the `--version` argv). Capture this output.

GREEN proof:
- Rewrite app/canary/Main.hs + the canary cabal build-depends. Run `./gate.sh` again; it must now pass through to the end. Capture the tail.

Commit subject:
- feat(canary): wire withCli + versionOption (gains --version)

Report back:
- Files changed.
- RED evidence (./gate.sh failing on the --version smoke before the canary rewrite).
- GREEN evidence (./gate.sh passing end-to-end after the canary rewrite, including both smoke lines).
- Commit short-sha + Tasks: trailer.
- Note any unexpected interaction with the live update-check codepath (e.g., did the canary surface a real banner during the gate? — if so, capture the line).
```

---

## Phase 6: Slice S4 — README rewrite around the `withCli` one-liner (US3, P3)

**Goal**: README's primary "Usage" example uses `withCli`, with the existing `defaultConfig` / `withUpdateCheck` API still documented as the raw-control alternative. Inlined ~6-line consumer example links to [`cardano-tx-tools#27`](https://github.com/lambdasistemi/cardano-tx-tools/issues/27) as the downstream call site.

**Owner**: orchestrator (docs only, no behavior change — this is a `docs:`-typed commit, no `Tasks:` trailer required).

### Tasks for slice S4

- [ ] T010 [US3] ORCHESTRATOR-OWNED, docs only — Rewrite the "Usage" section of `README.md`. Lead example: a ~6-line `Main.hs` using `withCli` (mirroring [`quickstart.md` § 2](./quickstart.md#2-replace-the-8-line-stanza-with-one-call)). Secondary "Raw control" section: keep the `defaultConfig` + `withUpdateCheck` example referencing the existing exports. Add a "`--version` flag" subsection pointing to `github-release-check:optparse` and showing the `<**> versionOption banner` plumbing. Footnote: `cardano-tx-tools#27` as the downstream migration ticket. Commit as one bisect-safe `docs(readme): rewrite Usage section around withCli one-liner` commit — no `Tasks:` trailer required (per `commit_gate` rule: docs-typed commits skip the trailer).

**Checkpoint**: After slice S4 ships, P3 acceptance scenarios (#1, #2, #3) hold.

---

## Phase 7: Polish & Finalization — Slice S5 (orchestrator)

**Goal**: Finalization audit passes; `gate.sh` is dropped in the final commit so the PR can move to ready.

**Owner**: orchestrator (chore only).

### Tasks for slice S5

- [ ] T011 ORCHESTRATOR-OWNED, finalization audit — Run the `finalization_audit <pr>` helper from the `resolve-ticket` skill. Verify every prior commit passes `commit_gate`; every behaviour-changing commit carries a `Tasks:` trailer; every closed task in `tasks.md` carries `[X] T### (commit: <sha>)`; `./gate.sh` is green at HEAD; README, contracts, quickstart, repository metadata are aligned with delivered behaviour; PR body is current.
- [ ] T012 ORCHESTRATOR-OWNED, chore only — `git rm gate.sh && git commit -S -m "chore: drop gate.sh (ready for review)"`. Push. `gh pr ready 6`. This is the only commit allowed in slice S5; it must be the tip commit of the branch.

**Checkpoint**: After S5, the PR moves to ready-for-external-review. Per resolve-ticket: do NOT self-approve via `gh pr review --approve`.

---

## Dependencies

```text
S1 ──▶ S2 ──▶ S3 ──▶ S4 ──▶ S5
```

- **S2 depends on S1**: `versionOption` takes a `CliBanner` value defined in S1.
- **S3 depends on S1 and S2**: the canary uses both helpers.
- **S4 depends on S1, S2, S3**: README documents the actual delivered surface and points at the in-repo canary as the reference example.
- **S5 depends on everything**: finalization audit can only pass once every preceding slice has shipped and `tasks.md` is fully `[X]`.

No two slices are parallelizable — each is a strict prerequisite of the next.

## Parallel Execution

None within a slice (every task in a slice belongs to the same commit). None across slices (strict dependency chain above).

## Implementation Strategy

**MVP scope**: Slice S1 alone is the MVP. After S1 ships, the P1 user story is satisfied: a consumer can adopt the one-liner today. S2 unlocks P2 (the `--version` flag), S3 dogfoods both internally and seals the live-boundary smoke, S4 communicates the new surface to readers, and S5 closes the PR for external review.

**One subagent at a time**: per the user's standing preference, the orchestrator dispatches one slice at a time, reviews the returned commit (rerunning `./gate.sh` locally and `commit_gate <sha>`), marks `tasks.md`, amends the slice commit so the `tasks.md` checkmark rides with the code, then dispatches the next slice. No parallel subagents on this PR.
