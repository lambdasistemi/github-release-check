{- |
Module      : GitHub.Release.Check.Cli
Description : One-liner consumer wrapper for the update check
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Bundles the four values every consumer would otherwise pass
piecemeal — repo, executable name, version, and opt-out env-var
name — into 'CliBanner', and exposes two helpers:

* 'composeCliConfig' assembles the final 'Config' by chaining
  'defaultConfig', a consumer-supplied modifier, and an env-var
  kill switch (the env-var wins).
* 'withCli' wraps the consumer action in 'withUpdateCheck' using
  that composed 'Config'.

The env-var kill switch is applied last so a careless consumer
modifier cannot silently re-enable a user's opt-out.
-}
module GitHub.Release.Check.Cli
    ( CliBanner (..)
    , composeCliConfig
    , withCli
    ) where

import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Version (Version)
import System.Environment (lookupEnv)

import GitHub.Release.Check.Engine
    ( Config (..)
    , defaultConfig
    , withUpdateCheck
    )
import GitHub.Release.Check.Fetcher (RepoSlug)

{- | The bundle of values every consumer hands to the update
check: which repo to poll, what executable name to render in
the banner, the locally-installed version, and the name of the
opt-out environment variable.
-}
data CliBanner = CliBanner
    { cliRepo :: !RepoSlug
    -- ^ owner\/name pair to query
    , cliExe :: !Text
    -- ^ executable name used in the banner and cache subdir
    , cliVersion :: !Version
    -- ^ locally-installed version (typically
    --   @Paths_<pkg>.version@)
    , cliOptOutEnvVar :: !String
    -- ^ environment variable that disables the check when set
    --   to any value (including the empty string)
    }

{- | Build the final 'Config' that 'withCli' would pass to
'withUpdateCheck'. Pipeline:

1. seed with 'defaultConfig' for the banner's repo \/ exe \/
   version;
2. apply the consumer's @'Config' -> 'Config'@ modifier;
3. if @'cliOptOutEnvVar' b@ is present in the environment,
   force @'cfgDisabled' = 'True'@ (env-var wins over the
   modifier).

Exposed separately from 'withCli' so tests and consumers can
inspect the assembled 'Config' without entering the
'withUpdateCheck' pipeline.
-}
composeCliConfig
    :: CliBanner
    -> (Config -> Config)
    -> IO Config
composeCliConfig b f = do
    base <- defaultConfig (cliRepo b) (cliExe b) (cliVersion b)
    let modified = f base
    disabled <- isJust <$> lookupEnv (cliOptOutEnvVar b)
    pure
        ( if disabled
            then modified{cfgDisabled = True}
            else modified
        )

{- | One-liner that composes the 'Config' from a 'CliBanner' plus
a modifier and wraps the inner action in 'withUpdateCheck'.

Equivalent to:

@
withCli b f action = do
    cfg <- 'composeCliConfig' b f
    'withUpdateCheck' cfg action
@
-}
withCli
    :: CliBanner
    -> (Config -> Config)
    -> IO a
    -> IO a
withCli b f action = do
    cfg <- composeCliConfig b f
    withUpdateCheck cfg action
