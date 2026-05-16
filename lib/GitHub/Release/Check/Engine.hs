{- |
Module      : GitHub.Release.Check.Engine
Description : Banner-on-exit update check engine
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

The leaf engine module of @github-release-check@. Holds the
'Config' record, 'defaultConfig' seeder, the 'withUpdateCheck' /
'runUpdateCheck' entry points, and the 'renderBanner' helper.

Re-exported in full from the umbrella module
'GitHub.Release.Check'. Consumers can import this module directly
when they want to keep the public surface minimal.
-}
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

import Control.Exception
    ( SomeException
    , finally
    , try
    )
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time.Clock.POSIX
    ( POSIXTime
    , getPOSIXTime
    )
import Data.Version (Version, showVersion)
import System.IO (stderr)

import GitHub.Release.Check.Cache
    ( defaultCachePath
    , readState
    , writeState
    )
import GitHub.Release.Check.Decision
import GitHub.Release.Check.Fetcher

-- | The runtime configuration for one update check.
data Config = Config
    { cfgRepo :: !RepoSlug
    -- ^ owner/name pair to query
    , cfgExeName :: !Text
    -- ^ human-readable name used in the banner and the
    --   default cache directory
    , cfgCurrentVersion :: !Version
    -- ^ the locally-installed version (typically
    --   @Paths_<pkg>.version@)
    , cfgCachePath :: !FilePath
    -- ^ where to persist 'State' between runs
    , cfgCheckInterval :: !POSIXTime
    -- ^ minimum seconds between GitHub hits
    , cfgBannerInterval :: !POSIXTime
    -- ^ minimum seconds between banner prints
    , cfgTimeoutMicros :: !Int
    -- ^ per-fetch timeout in microseconds
    , cfgPrint :: !(Text -> IO ())
    -- ^ where the banner goes (defaults to @stderr@)
    , cfgFetcher :: !Fetcher
    -- ^ HTTP backend; override for tests
    , cfgDisabled :: !Bool
    -- ^ caller-resolved kill switch (e.g. read from an
    --   env var). When 'True', the check is a no-op.
    }

{- | Build a 'Config' with sensible defaults:

* one-hour check interval and one-hour banner interval;
* two-second HTTP timeout;
* cache at @$XDG_CACHE_HOME\/\<exe\>\/update-check.json@;
* banner emitted via 'TIO.hPutStrLn' to @stderr@;
* live HTTPS fetcher;
* enabled (the caller chooses how to read its opt-out env var).
-}
defaultConfig
    :: RepoSlug
    -> Text
    -- ^ exe name (used in banner + cache path)
    -> Version
    -> IO Config
defaultConfig repo exe ver = do
    cache <- defaultCachePath exe
    pure
        Config
            { cfgRepo = repo
            , cfgExeName = exe
            , cfgCurrentVersion = ver
            , cfgCachePath = cache
            , cfgCheckInterval = 3600
            , cfgBannerInterval = 3600
            , cfgTimeoutMicros = 2_000_000
            , cfgPrint = TIO.hPutStrLn stderr
            , cfgFetcher = httpFetcher
            , cfgDisabled = False
            }

{- | @withUpdateCheck cfg action@ runs @action@ and, on exit
(including via exception), invokes 'runUpdateCheck'. The check is
guarded so failures inside it cannot affect @action@'s outcome.
-}
withUpdateCheck :: Config -> IO a -> IO a
withUpdateCheck cfg action = action `finally` runUpdateCheck cfg

{- | Run the check once. Catches every synchronous exception so the
caller does not have to. Safe to call from any context.
-}
runUpdateCheck :: Config -> IO ()
runUpdateCheck cfg
    | cfgDisabled cfg = pure ()
    | otherwise = do
        e <- try @SomeException (runUnsafe cfg)
        case e of
            Left _ -> pure ()
            Right () -> pure ()

runUnsafe :: Config -> IO ()
runUnsafe cfg = do
    st0 <- readState (cfgCachePath cfg)
    now <- getPOSIXTime
    st1 <-
        if shouldFetch (cfgCheckInterval cfg) now st0
            then do
                mLatest <-
                    cfgFetcher
                        cfg
                        (cfgTimeoutMicros cfg)
                        (cfgRepo cfg)
                let merged =
                        st0
                            { stLastCheckEpoch = Just now
                            , stLastKnownLatest =
                                case mLatest of
                                    Just v -> Just v
                                    Nothing -> stLastKnownLatest st0
                            }
                writeState (cfgCachePath cfg) merged
                pure merged
            else pure st0
    case decideBanner
        (cfgCurrentVersion cfg)
        (cfgBannerInterval cfg)
        now
        st1 of
        NoBanner -> pure ()
        PrintBanner latest -> do
            cfgPrint cfg (renderBanner cfg latest)
            writeState
                (cfgCachePath cfg)
                st1{stLastBannerEpoch = Just now}

{- | Render the default two-line banner:

@
\<exe\> \<current\> — a newer release \<latest\> is available
https:\/\/github.com\/\<owner\>\/\<name\>\/releases\/latest
@
-}
renderBanner :: Config -> Version -> Text
renderBanner cfg latest =
    T.intercalate
        "\n"
        [ T.concat
            [ cfgExeName cfg
            , " "
            , T.pack (showVersion (cfgCurrentVersion cfg))
            , " — a newer release "
            , T.pack (showVersion latest)
            , " is available"
            ]
        , T.concat
            [ "https://github.com/"
            , rsOwner (cfgRepo cfg)
            , "/"
            , rsName (cfgRepo cfg)
            , "/releases/latest"
            ]
        ]
