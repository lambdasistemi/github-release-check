# Research: `withCli` + `versionOption` helpers

## Decision 1 — Module placement for `withCli`

**Decision**: New sibling module `GitHub.Release.Check.Cli`, re-exported from the umbrella `GitHub.Release.Check`.

**Rationale**: Matches the established sibling-module pattern already used for `Cache`, `Decision`, and `Fetcher`. Keeps the consumer's import list to one symbol (`import GitHub.Release.Check`) without growing the umbrella module's source file. Follows the "Separate modules always" rule in the user's standing feedback.

**Alternatives considered**:
- Folding `withCli` directly into `GitHub.Release.Check.hs`. Rejected: violates the sibling-module convention and makes the umbrella source grow with every helper.
- New top-level module `GitHub.Cli` or `GitHub.Release.Cli`. Rejected: inconsistent with the existing namespace (`GitHub.Release.Check.*`).

## Decision 2 — Packaging of `versionOption`

**Decision**: Dedicated Cabal sublibrary `github-release-check:optparse` exposing one module `GitHub.Release.Check.OptParse`.

**Rationale**: Resolved by `/speckit.clarify` 2026-05-16 Q1. The sublibrary is the only zero-leak way to keep `optparse-applicative` off the core library's `build-depends` — every polymorphic alternative still surfaces `Parser` / `Mod OptionFields` types in the core API. Consumers who only want `withCli` pay no transitive `optparse-applicative` cost (SC-003).

**Alternatives considered**:
- Polymorphic `versionOption` taking the consumer's parser-applicative. Rejected: still leaks optparse types into the core public API.
- `renderVersion :: CliBanner -> String` in core + consumer writes 3 tokens of `infoOption` themselves. Rejected: reintroduces duplication, defeats P2's purpose.
- Both (core has `renderVersion`, sublibrary has `versionOption`). Rejected: doubles API surface for one feature; the sublibrary alone is sufficient.

## Decision 3 — `withCli` shape and Config composition order

**Decision**: `withCli :: CliBanner -> (Config -> Config) -> IO a -> IO a`. Composition order: `defaultConfig` → apply consumer modifier → apply env-var kill switch (last writer wins, kill switch wins).

**Rationale**: Resolved by `/speckit.clarify` 2026-05-16 Q2. The modifier preserves the one-liner promise of P1 even when consumers need to override `cfgCheckInterval`, `cfgPrint`, etc. Putting the env-var kill switch *after* the modifier preserves the documented opt-out invariant — a careless modifier cannot silently re-enable a user's `EXE_NO_UPDATE_CHECK=1`. Documented as acceptance scenario P1#6 in the spec.

**Alternatives considered**:
- No modifier (`withCli :: CliBanner -> IO a -> IO a`). Rejected: any tweak (custom cache dir, alternate print sink) forces a fallback to the 8-line stanza, undermining P1.
- Modifier as a field of `CliBanner` (`cliConfigOverrides :: Config -> Config`). Rejected: travels with the data the consumer treats as immutable identity; cleaner to keep the override as a per-call lever.
- Modifier applied *after* the env-var kill switch (so modifier wins). Rejected: a consumer modifier shouldn't override the user's intent expressed via an env-var, and silent kill-switch defeat is a footgun.

## Decision 4 — Exposing `composeCliConfig` for testability

**Decision**: `composeCliConfig :: CliBanner -> (Config -> Config) -> IO Config` is exported alongside `withCli` (from `GitHub.Release.Check.Cli` and re-exported through `GitHub.Release.Check`). `withCli b f action = composeCliConfig b f >>= \cfg -> withUpdateCheck cfg action`.

**Rationale**: The composed `Config` is the only observable output of the helper that doesn't require running `withUpdateCheck`'s I/O pipeline. Exposing the pure-but-`IO` composition (it is `IO` only because `defaultConfig` is `IO`, to read the XDG cache path) lets `CliSpec` assert (env unset, env set, modifier-vs-kill-switch precedence) without faking the cache file or the HTTP fetcher. It also gives consumers an escape hatch if they want the assembled `Config` for some other purpose (e.g., to feed `runUpdateCheck` directly).

**Alternatives considered**:
- Keep composition private; test indirectly via a fake `cfgFetcher` and `cfgPrint`. Rejected: forces every test to set up tmpdir cache + record calls; brittle, more LOC, and tests behaviour through three layers.
- Pure pre-step `composeCliConfigPure :: CliBanner -> (Config -> Config) -> Config -> Config` that doesn't read the cache path. Rejected: forces a `defaultConfig` call at every test site and gains nothing over exposing the `IO` version.

## Decision 5 — `versionOption` shape

**Decision**: `versionOption :: CliBanner -> Parser (a -> a)`, implemented as `infoOption (renderVersion banner) (long "version" <> help "Show the version and exit")`. `renderVersion :: CliBanner -> String` is a tiny pure helper kept private to `GitHub.Release.Check.OptParse` (consumers don't need it directly).

**Rationale**: Standard `optparse-applicative` `<**>` plumbing pattern. The output is exactly `<exe> <semver>` (from `cliExe` + `cliVersion`) on a single line; exit code 0 is the standard `infoOption` short-circuit behaviour.

**Alternatives considered**:
- Short flag `-v`. Rejected: too easy to clash with consumer flags (`--verbose` is a common companion); long-form-only matches modern CLI conventions (cargo, go, kubectl).
- Custom help text. Default `"Show the version and exit"` is generic enough; consumers who want different wording can write their own `infoOption` against `renderVersion`-equivalent if we ever export it.

## Decision 6 — Canary `--version` wiring

**Decision**: Canary's `Main` becomes:

```haskell
main = do
    opts <- execParser (info (pure () <**> versionOption banner <**> helper) idm)
    withCli banner id $ do
        ...  -- existing single-line putStrLn body
    where banner = CliBanner {...}
```

Both `withCli` and `versionOption` consume the same `banner :: CliBanner` value (DRY for repo slug, exe name, version, env-var name).

**Rationale**: Mirrors what the README example will show and what `cardano-tx-tools` consumers will write. The canary's job is to be a representative call site, not a minimal one.

**Alternatives considered**:
- Keep canary's existing inline `lookupEnv` + `defaultConfig` and add only `--version`. Rejected: defeats the dogfood goal (FR-008).
- Use `withCli banner` with a non-`id` modifier just to exercise the modifier path. Rejected: the canary should look like the README example, not like a test fixture; modifier-path coverage lives in `CliSpec`.

## Decision 7 — Sublibrary mechanics + test-suite dep wiring

**Decision**: Add a `library optparse` section to `github-release-check.cabal` with `exposed-modules: GitHub.Release.Check.OptParse`, `hs-source-dirs: lib`, `build-depends: github-release-check, optparse-applicative >= 0.18 && < 0.20, text`. The unit-tests suite adds `github-release-check:optparse` to its `build-depends`. The canary executable adds the same.

**Rationale**: `cabal-version: 3.4` (already declared) supports sublibraries via the `library <name>` syntax. The sublibrary depends on the core library, not the other way around, so the dep cycle is clean. Sharing `hs-source-dirs: lib` keeps the source tree flat.

**Alternatives considered**:
- Split `optparse-applicative` glue into a separate package. Rejected: heavyweight for one helper; would require its own release cadence.
- Make the sublibrary `internal: True` (private). Rejected: consumers need to depend on it, so it MUST be public.

**Risks**:
- Stack-based consumers occasionally need an explicit `library:` stanza in `stack.yaml`. Non-blocking — this project is not Stack-supported.

## Decision 8 — Test approach for `versionOption`

**Decision**: Use `Options.Applicative.execParserPure` + the `ParserResult` constructors (`Success`, `Failure`) to drive the parser in-process. The `--version` case returns `Failure` carrying a `ParserFailure` whose rendered output equals `"<exe> <semver>\n"` and whose `errorContext.exitCode` is `ExitSuccess`.

**Rationale**: Pure, fast, deterministic. Avoids spawning subprocesses from hspec. Confirms the `infoOption` wiring without going through `main`.

**Alternatives considered**:
- Subprocess via `process` package. Rejected: slow, brittle, and the canary smoke (S3 in `gate.sh`) already covers the actual-binary path.

## Decision 9 — No CI workflow changes

**Decision**: No GitHub Actions or other CI config edited by this feature. The pre-existing `nix flake check` gate already invokes the build, test, format, and hlint steps. The new canary smoke is added to the local `gate.sh` only (the per-PR mechanical gate); when the feature ships and `gate.sh` is dropped, the canary smoke becomes follow-up work for the project's `just ci` recipe if desired (out of scope for this PR — flagged for a separate ticket).

**Rationale**: Keep this PR's blast radius confined to the helpers + canary + docs. CI evolution is a separate concern.

**Alternatives considered**:
- Fold the canary smoke into `justfile` permanently. Deferred — out of scope; can be a 1-line follow-up.
