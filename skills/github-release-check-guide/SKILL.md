---
name: github-release-check-guide
description: >-
  Use when working in the lambdasistemi/github-release-check repository —
  a small Haskell library that prints an "a newer release is available"
  update banner on stderr when a CLI is behind its latest GitHub release.
  Load for tasks touching withUpdateCheck, withCli, composeCliConfig,
  CliBanner, defaultConfig, Config, RepoSlug, Fetcher, httpFetcher,
  parseTagName, decideBanner, shouldFetch, renderBanner, the State cache
  record, the versionOption --version flag in the github-release-check:optparse
  sublibrary, or the github-release-check-canary executable. Also load for
  questions about the update-check.json cache (lastCheckEpoch /
  lastKnownLatest / lastBannerEpoch), the cfgCheckInterval / cfgBannerInterval
  / cfgTimeoutMicros knobs, the *_NO_UPDATE_CHECK opt-out env var, the
  GitHub Releases API call (/repos/:owner/:repo/releases/latest), or the
  nix flake (just unit, just format, nix flake check, nix run .#canary).
  Modules live under lib/GitHub/Release/Check/ and lib-optparse/.
---

# github-release-check guide

## Repository map

| Path | Purpose |
| --- | --- |
| `lib/GitHub/Release/Check.hs` | Umbrella module; re-exports `Cli`, `Decision`, `Engine`, `Fetcher`. Consumers `import GitHub.Release.Check`. |
| `lib/GitHub/Release/Check/Cli.hs` | `CliBanner` record + `withCli` one-liner + `composeCliConfig`. The consumer-facing layer; applies the env-var kill switch last. |
| `lib/GitHub/Release/Check/Engine.hs` | `Config`, `defaultConfig`, `withUpdateCheck`/`runUpdateCheck` (the on-exit loop), `renderBanner`. The IO shell. |
| `lib/GitHub/Release/Check/Decision.hs` | Pure logic: `State` cache record, `shouldFetch`, `decideBanner`, `Banner`. No IO. |
| `lib/GitHub/Release/Check/Cache.hs` | JSON read/write of `State` to `update-check.json`; `defaultCachePath`. Permissive — any error is `emptyState`. |
| `lib/GitHub/Release/Check/Fetcher.hs` | `RepoSlug`, the `Fetcher` type, `httpFetcher` (calls the GitHub Releases API), `parseTagName`. |
| `lib-optparse/GitHub/Release/Check/OptParse.hs` | The `github-release-check:optparse` sublibrary: `versionOption` info-flag. Isolated so the core library has no `optparse-applicative` dependency. |
| `app/canary/Main.hs` | `github-release-check-canary` executable; dogfoods `withCli` + `versionOption` against this repo. |
| `test/` | hspec suites: `CacheSpec`, `CliSpec`, `DecisionSpec`, `OptParseSpec` (discovered by `hspec-discover` from `Spec.hs`). |
| `github-release-check.cabal` | Package: `library`, `library optparse` (public sublibrary), the canary `executable`, and `unit-tests`. |
| `flake.nix`, `nix/*.nix` | haskell.nix project (GHC 9.12.3), flake checks/apps, devshell. |
| `justfile` | `build`, `unit`, `format`, `format-check`, `hlint`, `ci` recipes. |

## Build, test, run

Enter the dev shell first: `nix develop --quiet`.

- `just build` — `cabal build all -O0 --enable-tests`
- `just unit` — `cabal test unit-tests -O0 --test-show-details=direct`;
  `just unit "<match>"` passes `--match` to hspec
- `just format` — fourmolu (3 passes) + `cabal-fmt` + `nixfmt`
- `just format-check` — non-mutating format gate (CI)
- `just hlint` — `hlint lib lib-optparse test`
- `nix flake check` — realises the `build`, `unit`, `lint`, `canary`
  checks (the full local CI mirror)
- `nix run .#canary` — runs the canary executable live against the
  real GitHub API; `nix run .#canary -- --version` prints the version

Note the env-var split between the canary *check* and the canary *app*:
`nix/checks.nix` sets `GITHUB_RELEASE_CHECK_CANARY_NO_UPDATE_CHECK=1`
so the sandboxed CI check stays hermetic, while `flake.nix` overrides
`apps.canary` to the raw executable so `nix run .#canary` actually hits
the network.

## Navigating the code

- **Entry point a consumer uses:** `withCli` in `Cli.hs`. It calls
  `composeCliConfig` (seed `defaultConfig`, apply the consumer's
  `Config -> Config` modifier, then force `cfgDisabled = True` if the
  opt-out env var is set) and hands the `Config` to `withUpdateCheck`.
- **The on-exit loop:** `withUpdateCheck` runs the action and then
  `runUpdateCheck cfg` in a `finally`, in `Engine.hs`. `runUpdateCheck`
  swallows every synchronous exception. The real work is `runUnsafe`:
  `readState` →
  `getPOSIXTime` → `shouldFetch` gate → maybe `cfgFetcher` + `writeState`
  → `decideBanner` gate → maybe `cfgPrint (renderBanner …)` + `writeState`.
- **The two gates (pure):** `shouldFetch` and `decideBanner` in
  `Decision.hs`. Change banner/fetch timing rules here; they are unit
  tested in `DecisionSpec`.
- **The network call:** `httpFetcher` in `Fetcher.hs` — builds a fresh
  TLS manager, GETs `/repos/:owner/:repo/releases/latest`, parses
  `tag_name`, strips a leading `v`/`V`, returns `Maybe Version`. Every
  error path returns `Nothing`. Tag parsing is `parseTagName`.
- **The cache format:** `Cache.hs` `ToJSON`/`FromJSON State` — JSON keys
  `lastCheckEpoch`, `lastKnownLatest`, `lastBannerEpoch`; epochs stored
  as integer seconds. Path comes from `defaultCachePath`
  (`$XDG_CACHE_HOME/<exe>/update-check.json`).
- **The banner text:** `renderBanner` in `Engine.hs` — two lines:
  `"<exe> <current> — a newer release <latest> is available"` then the
  `…/releases/latest` URL.
- **`--version`:** `versionOption` in `OptParse.hs` (sublibrary), an
  `infoOption` rendering `"<cliExe> <showVersion cliVersion>"`.

## Using the library

Minimal wiring — wrap `main`:

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

Override defaults via the `Config -> Config` modifier (second `withCli`
argument). The env-var kill switch always wins over the modifier:

```haskell
main = withCli banner
    (\cfg -> cfg { cfgCheckInterval = 24 * 3600 }) -- daily, not hourly
    realMain
```

Add `--version` (needs `github-release-check:optparse` +
`optparse-applicative` in `build-depends`):

```haskell
import GitHub.Release.Check.OptParse (versionOption)
import Options.Applicative

main = do
    opts <- execParser $
        info (myParser <**> versionOption banner <**> helper) fullDesc
    withCli banner id (run opts)
```

For full manual control, use the raw entry points and resolve the
opt-out env var yourself:

```haskell
cfg <- defaultConfig (RepoSlug "lambdasistemi" "my-cli") "my-cli" version
withUpdateCheck cfg realMain
```

Defaults from `defaultConfig`: 1 h check interval, 1 h banner interval,
2 s (`2_000_000` µs) timeout, banner to stderr, live `httpFetcher`,
`cfgDisabled = False`.

## Answering questions

Present this as a tiny, dependency-light "upgrade nudge" library for
Haskell CLIs — not an auto-updater. When a user asks:

- **"How do I add the banner to my CLI?"** → README *Quickstart* /
  *Usage*; `withCli` in `lib/GitHub/Release/Check/Cli.hs`.
- **"How do I add `--version`?"** → README *`--version` flag*;
  `versionOption` in `lib-optparse/.../OptParse.hs`. Stress that it is a
  separate sublibrary so the core stays `optparse`-free.
- **"How do I turn it off?"** → set the `cliOptOutEnvVar` env var (any
  value, including empty). README *Opt-out*; logic in `composeCliConfig`.
- **"How often does it call GitHub / print?"** → two independent timers,
  `cfgCheckInterval` and `cfgBannerInterval`, both 1 h by default;
  rules in `Decision.hs` (`shouldFetch`, `decideBanner`).
- **"Where is the cache / what's in it?"** → `update-check.json` under
  `$XDG_CACHE_HOME/<exe>/`; fields `lastCheckEpoch`, `lastKnownLatest`,
  `lastBannerEpoch`. README *Cache file*; `Cache.hs`.
- **"What happens on network failure?"** → nothing visible; every error
  collapses to `Nothing`/`emptyState`. The check never throws and never
  affects exit code. `Fetcher.hs`, `Cache.hs`, `runUpdateCheck`.
- **"What's the canary?"** → the in-repo dogfood/CI guard; README
  *Canary*; `app/canary/Main.hs`, `nix/checks.nix`, `flake.nix`.

Always verify a claimed default, command, or JSON field against the
source before stating it — the modules above are the source of truth.
