# Public API Contract — `withCli` + `versionOption`

This is the pinned signature contract for the two new helpers. Any
deviation from these signatures during implementation requires a
plan amendment.

## Module `GitHub.Release.Check.Cli` (new, in core library)

```haskell
module GitHub.Release.Check.Cli
    ( CliBanner (..)
    , composeCliConfig
    , withCli
    ) where

import Data.Text (Text)
import Data.Version (Version)

import GitHub.Release.Check (Config)
import GitHub.Release.Check.Fetcher (RepoSlug)

data CliBanner = CliBanner
    { cliRepo         :: !RepoSlug
    , cliExe          :: !Text
    , cliVersion      :: !Version
    , cliOptOutEnvVar :: !String
    }

-- | Build the final 'Config' the helper would pass to
-- 'withUpdateCheck'. Pipeline: 'defaultConfig' → consumer modifier
-- → env-var kill switch (env-var wins).
composeCliConfig
    :: CliBanner
    -> (Config -> Config)
    -> IO Config

-- | One-liner wrapping 'withUpdateCheck'. Equivalent to:
--   @withCli b f act = composeCliConfig b f >>= \\cfg -> withUpdateCheck cfg act@
withCli
    :: CliBanner
    -> (Config -> Config)
    -> IO a
    -> IO a
```

## Module `GitHub.Release.Check` (existing, additive change only)

```haskell
module GitHub.Release.Check
    ( -- ... all existing exports preserved verbatim ...

      -- * Bundled CLI helper (new)
      module GitHub.Release.Check.Cli
    ) where

import GitHub.Release.Check.Cli
```

Re-export-only change. **No existing identifier is removed, renamed, or has its type changed.**

Specifically still exported, unchanged:

- `Config (..)`, `defaultConfig`
- `withUpdateCheck`, `runUpdateCheck`
- `module GitHub.Release.Check.Decision` (all of `Decision`)
- `module GitHub.Release.Check.Fetcher` (`RepoSlug`, `Fetcher`, `httpFetcher`, etc.)
- `renderBanner`

## Module `GitHub.Release.Check.OptParse` (new, in sublibrary `github-release-check:optparse`)

```haskell
module GitHub.Release.Check.OptParse
    ( versionOption
    ) where

import Options.Applicative (Parser)
import GitHub.Release.Check.Cli (CliBanner)

-- | An 'optparse-applicative' info option that prints
-- @"<cliExe banner> <showVersion (cliVersion banner)>"@ to stdout
-- and exits with 'ExitSuccess'. Plumb into a consumer parser via
-- '<**>'.
versionOption :: CliBanner -> Parser (a -> a)
```

`renderVersion :: CliBanner -> String` is the internal helper used to build the printed line; **not** exported from the sublibrary in this PR (consumers who need raw control can call `showVersion (cliVersion banner)` directly).

## Cabal manifest deltas

```cabal
-- existing `library` section: add the new module to exposed-modules
library
  exposed-modules:
    GitHub.Release.Check
    GitHub.Release.Check.Cache
    GitHub.Release.Check.Cli           -- NEW
    GitHub.Release.Check.Decision
    GitHub.Release.Check.Fetcher
  -- build-depends unchanged

-- NEW sublibrary
library optparse
  import:           warnings
  hs-source-dirs:   lib
  default-language: GHC2021
  exposed-modules:  GitHub.Release.Check.OptParse
  build-depends:
    , base
    , github-release-check
    , optparse-applicative >=0.18 && <0.20
    , text

-- existing canary executable: add sublibrary to build-depends
executable github-release-check-canary
  build-depends:
    , base
    , github-release-check
    , github-release-check:optparse    -- NEW
    , optparse-applicative >=0.18 && <0.20   -- NEW (canary uses execParser directly)
    , text

-- existing unit-tests test-suite: add sublibrary + opt-applicative dep + new modules
test-suite unit-tests
  other-modules:
    GitHub.Release.Check.CacheSpec
    GitHub.Release.Check.CliSpec       -- NEW
    GitHub.Release.Check.DecisionSpec
    GitHub.Release.Check.OptParseSpec  -- NEW
  build-depends:
    , aeson
    , base
    , bytestring
    , directory
    , filepath
    , github-release-check
    , github-release-check:optparse    -- NEW
    , hspec
    , optparse-applicative >=0.18 && <0.20   -- NEW (for execParserPure in OptParseSpec)
    , QuickCheck
    , temporary
    , text
    , time
```

## Backwards compatibility guarantee

| Surface | Before | After | Compatible? |
|---|---|---|---|
| `Config (..)` | unchanged | unchanged | ✅ |
| `defaultConfig`, `withUpdateCheck`, `runUpdateCheck` | unchanged | unchanged | ✅ |
| `RepoSlug` | unchanged | unchanged | ✅ |
| `renderBanner` | unchanged | unchanged | ✅ |
| Re-exports of `Decision`, `Fetcher` | unchanged | unchanged | ✅ |
| Cache file format / location | unchanged | unchanged | ✅ |
| Network behaviour (URL, headers, timeout default) | unchanged | unchanged | ✅ |
| `optparse-applicative` in **core** `build-depends` | absent | absent | ✅ |
| `optparse-applicative` in **sublibrary** `build-depends` | n/a | added | ✅ (sublibrary is opt-in) |

A consumer with no source changes who upgrades to the post-feature version MUST continue to compile and behave identically.
