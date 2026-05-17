# github-release-check

A small Haskell library that prints an _update banner_ on stderr when a
CLI is behind its latest GitHub release.

Designed for small, on-prem CLIs where:

- the executable is published to GitHub Releases under a `v<semver>`
  tag,
- users install via Homebrew, AppImage, DEB, or `cabal install`, and
- you want a polite, rate-limited reminder that a newer version is
  available — without forcing an opinionated auto-updater on anyone.

## Usage

The one-liner that bundles env-var opt-out, `defaultConfig`, and
`withUpdateCheck` into a single call:

```haskell
import GitHub.Release.Check
import Paths_my_cli (version)

main :: IO ()
main = withCli banner id realMain

banner :: CliBanner
banner = CliBanner
    { cliRepo         = RepoSlug "lambdasistemi" "my-cli"
    , cliExe          = "my-cli"
    , cliVersion      = version
    , cliOptOutEnvVar = "MY_CLI_NO_UPDATE_CHECK"
    }
```

After `realMain` returns — or throws — the check fires:

- if the cache is older than the check interval (default 1 h), it hits
  `https://api.github.com/repos/<owner>/<name>/releases/latest` with a
  2 s timeout;
- if the latest release is greater than the configured current version
  and the banner has not printed within the banner interval
  (default 1 h), it emits a two-line banner to stderr.

The check **never throws**, never affects the wrapped action's exit
code, and silently skips on any network or parse failure.

### Overriding `Config` fields

The `id` is the `Config -> Config` modifier. Pass it when the defaults
are fine. Pass something else when they aren't:

```haskell
main = withCli banner
    (\cfg -> cfg { cfgCheckInterval = 24 * 3600   -- daily, not hourly
                 , cfgPrint         = T.IO.putStrLn  -- banner to stdout
                 })
    realMain
```

The env-var kill switch (`MY_CLI_NO_UPDATE_CHECK` in the example
above) **takes precedence over the modifier**: setting the env var
disables the check even if the modifier sets `cfgDisabled = False`.
This protects users who opt out from a careless library upgrade.

### `--version` flag

The optional `github-release-check:optparse` sublibrary exposes a
matching `versionOption` info-flag that prints `<exe> <semver>` and
exits `0`, drawing the exe name and version from the same `CliBanner`
record. Add it to your `build-depends`:

```cabal
build-depends:
  , github-release-check
  , github-release-check:optparse   -- only if you want --version
  , optparse-applicative
```

Then plumb it into your parser:

```haskell
import Options.Applicative
import GitHub.Release.Check.OptParse (versionOption)

main :: IO ()
main = do
    opts <- execParser $
        info
            (myParser <**> versionOption banner <**> helper)
            (fullDesc <> progDesc "...")
    withCli banner id (run opts)
```

`my-cli --version` now prints `my-cli <semver>` and exits `0`. The
core library does **not** depend on `optparse-applicative` — consumers
that only want `withCli` pay no transitive cost.

### Raw control

`withCli` is sugar over the lower-level entry points, which remain
exported. Use them when you need full control of the `Config`
assembly:

```haskell
import GitHub.Release.Check
import Paths_my_cli (version)

main :: IO ()
main = do
    cfg <- defaultConfig
        (RepoSlug "lambdasistemi" "my-cli")
        "my-cli"
        version
    withUpdateCheck cfg realMain
```

The opt-out env var is then the caller's responsibility (read it via
`lookupEnv` and set `cfgDisabled` on the `Config`).

## Configuration

```haskell
data Config = Config
    { cfgRepo           :: RepoSlug
    , cfgExeName        :: Text
    , cfgCurrentVersion :: Version
    , cfgCachePath      :: FilePath
    , cfgCheckInterval  :: POSIXTime     -- seconds
    , cfgBannerInterval :: POSIXTime
    , cfgTimeoutMicros  :: Int
    , cfgPrint          :: Text -> IO ()
    , cfgFetcher        :: Fetcher       -- HTTP backend (override-able)
    , cfgDisabled       :: Bool          -- caller-resolved kill switch
    }
```

`defaultConfig` fills in the standard knobs; callers tweak the fields
they care about, either via the `withCli` modifier or directly on the
record.

### Opt-out

The library does not bake a default env-var name — that is the
caller's business (`cliOptOutEnvVar` in `CliBanner`). The recommended
convention is `<UPPER_SNAKE_EXE_NAME>_NO_UPDATE_CHECK`, e.g.
`MY_CLI_NO_UPDATE_CHECK`. Any value (including the empty string) is
treated as "disable"; only unsetting the variable re-enables the
check.

### Cache file

Default location: `$XDG_CACHE_HOME/<exe>/update-check.json`.

```json
{
  "lastCheckEpoch": 1700000000,
  "lastKnownLatest": "0.2.10.0",
  "lastBannerEpoch": 1700000100
}
```

## Real-world consumer

[`cardano-tx-tools`](https://github.com/lambdasistemi/cardano-tx-tools)
ships four executables that all use `withCli` for the upgrade banner
and `versionOption` for `--version`. The migration is tracked in
[lambdasistemi/cardano-tx-tools#27](https://github.com/lambdasistemi/cardano-tx-tools/issues/27).

## Development

```bash
nix develop --quiet
just unit          # cabal test unit-tests
just format        # fourmolu + cabal-fmt
just hlint
nix flake check    # full local CI mirror (build + unit + lint + canary)
```

### Canary

`github-release-check-canary` is a tiny executable that wires the
library against this repository, dogfooding both `withCli` and
`versionOption`. It runs in CI on every build (with the network call
disabled to keep the sandbox hermetic) and operators can invoke it
live to probe the real GitHub API:

```bash
nix run .#canary
# github-release-check-canary 0.1.0.0 — library wired against lambdasistemi/github-release-check

nix run .#canary -- --version
# github-release-check-canary 0.1.0.0
```

If a newer release is available the library prints its banner to
stderr after the canary line. Setting
`GITHUB_RELEASE_CHECK_CANARY_NO_UPDATE_CHECK=1` disables the check.

## License

Apache-2.0
