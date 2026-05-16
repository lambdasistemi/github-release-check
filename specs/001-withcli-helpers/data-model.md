# Data Model: `withCli` + `versionOption` helpers

This feature introduces one new entity (`CliBanner`) and one named composition pipeline (`composeCliConfig`). No persistent state, no schema migrations, no on-disk format changes.

## Entity — `CliBanner`

The bundle of values every consumer already passes piecemeal to `defaultConfig` + `lookupEnv`. Defined in `GitHub.Release.Check.Cli`, re-exported from `GitHub.Release.Check`.

| Field | Type | Source / Constraint | Notes |
|---|---|---|---|
| `cliRepo` | `RepoSlug` | reused from `GitHub.Release.Check.Fetcher` | owner + name of the GitHub repo to query |
| `cliExe` | `Text` | required | human-readable executable name (used in banner and as the cache subdirectory key, mirroring `cfgExeName`) |
| `cliVersion` | `Version` | required (typically `Paths_<pkg>.version`) | local executable version |
| `cliOptOutEnvVar` | `String` | required, caller-supplied; no default | `lookupEnv` key; if the variable is *present* (any value, including `""`), the update check is disabled. The library does NOT bake a default name (per FR-007). |

Type-class derivations: none required. Pattern-match in tests via `RecordWildCards` (already on by default in this project's `default-extensions`).

Constructor pattern (suggested): regular record with `NamedFieldPuns` use sites.

## Composition Pipeline — `composeCliConfig`

`composeCliConfig :: CliBanner -> (Config -> Config) -> IO Config`

Pipeline in execution order:

1. **Seed** — `base <- defaultConfig (cliRepo b) (cliExe b) (cliVersion b)`. Pulls `cfgCachePath`, all interval/timeout defaults, the default `cfgPrint` to stderr, and `httpFetcher` from `defaultConfig`. `cfgDisabled` is `False`.
2. **Modifier** — `let modified = f base`. Consumer overrides anything (cache path, intervals, print sink, fetcher, …). The modifier sees the seeded `Config`, including `cfgDisabled = False`, and may toggle it.
3. **Kill switch** — `disabled <- isJust <$> lookupEnv (cliOptOutEnvVar b)`. If `True`, override `modified { cfgDisabled = True }`. If `False`, keep `modified` as-is (so the consumer's modifier value of `cfgDisabled` is preserved).

The pipeline produces the final `Config` consumed by `withUpdateCheck`. Truth table:

| env var | modifier's `cfgDisabled` | final `cfgDisabled` |
|---|---|---|
| unset | `False` (default) | `False` (check runs) |
| unset | `True` (modifier disables) | `True` (modifier wins when env unset) |
| set   | `False` (default) | `True` (env-var kill switch wins) |
| set   | `True` (modifier also disables) | `True` (both agree) |
| set   | `False` (modifier *re-enables*) | **`True`** (env-var kill switch wins — FR-002) |

This last row is the documented invariant: a careless modifier cannot silently re-enable a user's opt-out.

## Helper — `withCli`

`withCli :: CliBanner -> (Config -> Config) -> IO a -> IO a`

Defined as:

```text
withCli b f action = do
    cfg <- composeCliConfig b f
    withUpdateCheck cfg action
```

No new state, no new side effects beyond what `composeCliConfig` and the existing `withUpdateCheck` already do.

## Helper — `versionOption`

`versionOption :: CliBanner -> Parser (a -> a)`

Defined in the sublibrary `github-release-check:optparse` (module `GitHub.Release.Check.OptParse`). Built on top of `optparse-applicative`'s `infoOption`:

```text
versionOption b =
    infoOption
        (renderVersion b)              -- "<cliExe b> <showVersion (cliVersion b)>"
        (long "version" <> help "Show the version and exit")
```

Plumbed at the consumer's call site via `<**>`:

```text
execParser (info (parser <**> versionOption banner <**> helper) idm)
```

No new entities; reuses `CliBanner` end-to-end.

## Non-changes

- `Config` itself: unchanged. All existing fields, types, defaults preserved.
- `defaultConfig`, `withUpdateCheck`, `runUpdateCheck`, `RepoSlug`, `renderBanner`, `Decision`, `Fetcher`: untouched. Re-exports from `GitHub.Release.Check` unchanged.
- On-disk cache format (`State`): untouched.
- HTTP fetcher behaviour: untouched.
