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

After `realMain` returns — or throws — the check fires:

- if the cache is older than the check interval (default 1 h), it hits
  `https://api.github.com/repos/<owner>/<name>/releases/latest` with a
  2 s timeout;
- if the latest release is greater than the configured current version
  and the banner has not printed within the banner interval
  (default 1 h), it emits a two-line banner to stderr.

The check **never throws**, never affects the wrapped action's exit
code, and silently skips on any network or parse failure.

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
they care about.

### Opt-out

The library does not read environment variables — that is the caller's
business. The recommended pattern:

```haskell
disabled <- isJust <$> lookupEnv "MY_CLI_NO_UPDATE_CHECK"
cfg <- defaultConfig (RepoSlug "owner" "my-cli") "my-cli" version
withUpdateCheck cfg { cfgDisabled = disabled } realMain
```

### Cache file

Default location: `$XDG_CACHE_HOME/<exe>/update-check.json`.

```json
{
  "lastCheckEpoch": 1700000000,
  "lastKnownLatest": "0.2.10.0",
  "lastBannerEpoch": 1700000100
}
```

## Development

```bash
nix develop --quiet
just unit          # cabal test unit-tests
just format        # fourmolu + cabal-fmt
just hlint
nix flake check    # full local CI mirror
```

## License

Apache-2.0
