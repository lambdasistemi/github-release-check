# Public API Contract — `withCli` + `versionOption`

This is the pinned signature contract for the two new helpers. Any
deviation from these signatures during implementation requires a
plan amendment.

## Module `GitHub.Release.Check.Engine` (new, in core library — refactor extracted from the umbrella)

To break the cycle between `Cli` (which needs `Config`, `defaultConfig`, `withUpdateCheck`) and the umbrella `GitHub.Release.Check` (which re-exports `module GitHub.Release.Check.Cli`), the engine definitions currently living in `lib/GitHub/Release/Check.hs` are extracted verbatim into a new leaf module.

```haskell
module GitHub.Release.Check.Engine
    ( -- * Configuration
      Config (..)
    , defaultConfig

      -- * Entry points
    , withUpdateCheck
    , runUpdateCheck

      -- * Banner rendering
    , renderBanner
    ) where
```

**Move, do not change**: `Config (..)`, `defaultConfig`, `withUpdateCheck`, `runUpdateCheck`, `renderBanner` (and the private `runUnsafe` helper) move from `GitHub.Release.Check.hs` to `GitHub.Release.Check.Engine.hs` **byte-for-byte**. No field renames, no signature tweaks, no haddock rewrites. The same imports (`GitHub.Release.Check.Cache`, `GitHub.Release.Check.Decision`, `GitHub.Release.Check.Fetcher`) move with them.

Result: `GitHub.Release.Check.Engine` is a leaf — depends only on `Cache`, `Decision`, `Fetcher` (which are also leaves). `Cli` then imports `Config`, `defaultConfig`, `withUpdateCheck` directly from `Engine` (no cycle). The umbrella becomes pure re-export plumbing.

## Module `GitHub.Release.Check.Cli` (new, in core library)

```haskell
module GitHub.Release.Check.Cli
    ( CliBanner (..)
    , composeCliConfig
    , withCli
    ) where

import Data.Text (Text)
import Data.Version (Version)

import GitHub.Release.Check.Engine (Config)
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

## Module `GitHub.Release.Check` (existing — becomes pure re-export plumbing)

After the S1 refactor the umbrella holds **no definitions** — only re-exports of its four leaf modules:

```haskell
module GitHub.Release.Check
    ( module GitHub.Release.Check.Cli
    , module GitHub.Release.Check.Decision
    , module GitHub.Release.Check.Engine
    , module GitHub.Release.Check.Fetcher
    ) where

import GitHub.Release.Check.Cli
import GitHub.Release.Check.Decision
import GitHub.Release.Check.Engine
import GitHub.Release.Check.Fetcher
```

The module header / haddock docstring at the top of `GitHub.Release.Check.hs` stays — it's the public-surface introduction the consumer reads first. The umbrella's import list and the re-export list change; nothing else.

**Consumer compatibility**: a consumer writing `import GitHub.Release.Check (Config (..), defaultConfig, withUpdateCheck, renderBanner, RepoSlug (..))` continues to compile unchanged. Re-export through the umbrella preserves the entire public surface.

Specifically still exported via the umbrella, unchanged for consumers:

- `Config (..)`, `defaultConfig` (now defined in `Engine`)
- `withUpdateCheck`, `runUpdateCheck` (now defined in `Engine`)
- `renderBanner` (now defined in `Engine`)
- `module GitHub.Release.Check.Decision` (all of `Decision`, unchanged)
- `module GitHub.Release.Check.Fetcher` (`RepoSlug`, `Fetcher`, `httpFetcher`, etc., unchanged)
- `CliBanner (..)`, `composeCliConfig`, `withCli` (new, defined in `Cli`)

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
-- existing `library` section: add two new modules to exposed-modules
library
  exposed-modules:
    GitHub.Release.Check
    GitHub.Release.Check.Cache
    GitHub.Release.Check.Cli           -- NEW
    GitHub.Release.Check.Decision
    GitHub.Release.Check.Engine        -- NEW (extracted from GitHub.Release.Check)
    GitHub.Release.Check.Fetcher
  -- build-depends unchanged

-- NEW sublibrary
-- NOTE on hs-source-dirs: the sublibrary uses its OWN directory
-- `lib-optparse/` (not `lib/`). Sharing `lib/` with the core library
-- would put `Cli.hs` on the sublibrary's module search path, GHC
-- would resolve `import GitHub.Release.Check.Cli` to the local source
-- file (instead of pulling it from the `github-release-check` package
-- dependency), and the sublibrary would end up needing every
-- transitive dep of the core library. Giving the sublibrary its own
-- directory containing only its own modules avoids that and keeps
-- the sublibrary's `build-depends` minimal (no `PackageImports`
-- extension needed).
library optparse
  import:           warnings
  hs-source-dirs:   lib-optparse
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
| `Config (..)` (re-exported via `GitHub.Release.Check`) | defined in umbrella | defined in `Engine`, re-exported via umbrella | ✅ |
| `defaultConfig`, `withUpdateCheck`, `runUpdateCheck` (re-exported via umbrella) | defined in umbrella | defined in `Engine`, re-exported via umbrella | ✅ |
| `RepoSlug` | unchanged | unchanged | ✅ |
| `renderBanner` (re-exported via umbrella) | defined in umbrella | defined in `Engine`, re-exported via umbrella | ✅ |
| Re-exports of `Decision`, `Fetcher` via umbrella | unchanged | unchanged | ✅ |
| Direct imports of `GitHub.Release.Check.Engine` | n/a | new, public | ✅ (additive) |
| Cache file format / location | unchanged | unchanged | ✅ |
| Network behaviour (URL, headers, timeout default) | unchanged | unchanged | ✅ |
| `optparse-applicative` in **core** `build-depends` | absent | absent | ✅ |
| `optparse-applicative` in **sublibrary** `build-depends` | n/a | added | ✅ (sublibrary is opt-in) |

A consumer with no source changes who upgrades to the post-feature version MUST continue to compile and behave identically.
