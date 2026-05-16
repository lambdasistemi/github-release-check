{- |
Module      : GitHub.Release.Check.Cache
Description : Disk-backed cache for the update check
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

JSON-backed cache that persists 'State' between invocations. Reads are
permissive — a missing, unreadable, or malformed file is treated as
'emptyState' so the cache cannot fail the check it backs.
-}
module GitHub.Release.Check.Cache
    ( readState
    , writeState
    , defaultCachePath
    ) where

import Control.Exception (SomeException, try)
import Data.Aeson
    ( FromJSON (..)
    , ToJSON (..)
    , eitherDecodeStrict'
    , encode
    , object
    , withObject
    , (.:?)
    , (.=)
    )
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock.POSIX (POSIXTime)
import Data.Version (Version, parseVersion, showVersion)
import System.Directory
    ( XdgDirectory (..)
    , createDirectoryIfMissing
    , getXdgDirectory
    )
import System.FilePath ((</>))
import Text.ParserCombinators.ReadP (readP_to_S)

import GitHub.Release.Check.Decision
    ( State (..)
    , emptyState
    )

instance ToJSON State where
    toJSON st =
        object
            [ "lastCheckEpoch"
                .= (fromIntegral . round @_ @Int <$> stLastCheckEpoch st :: Maybe Int)
            , "lastKnownLatest" .= (T.pack . showVersion <$> stLastKnownLatest st)
            , "lastBannerEpoch"
                .= (fromIntegral . round @_ @Int <$> stLastBannerEpoch st :: Maybe Int)
            ]

instance FromJSON State where
    parseJSON = withObject "State" $ \o -> do
        mCheck <- o .:? "lastCheckEpoch"
        mLatest <- o .:? "lastKnownLatest"
        mBanner <- o .:? "lastBannerEpoch"
        pure
            State
                { stLastCheckEpoch =
                    fmap (realToFrac @Int) mCheck
                , stLastKnownLatest = mLatest >>= parseVersionMay
                , stLastBannerEpoch =
                    fmap (realToFrac @Int) mBanner
                }

parseVersionMay :: Text -> Maybe Version
parseVersionMay t =
    case [v | (v, "") <- readP_to_S parseVersion (T.unpack t)] of
        (v : _) -> Just v
        [] -> Nothing

{- | Read the cache file. Any error — missing file, permission denied,
malformed JSON — collapses to 'emptyState'. The check must keep
working even when the cache cannot be honoured.
-}
readState :: FilePath -> IO State
readState path = do
    e <- try @SomeException (BS.readFile path)
    pure $ case e of
        Left _ -> emptyState
        Right bs -> case eitherDecodeStrict' bs of
            Left _ -> emptyState
            Right st -> st

{- | Write the cache file. Creates parent directories on the way. A
failure is swallowed; the cache is advisory, not load-bearing.
-}
writeState :: FilePath -> State -> IO ()
writeState path st = do
    _ <-
        try @SomeException $ do
            createDirectoryIfMissing True (parentOf path)
            BSL.writeFile path (encode st)
    pure ()
  where
    parentOf p =
        let r = reverse p
        in  case dropWhile (/= '/') r of
                ('/' : rs) -> reverse rs
                _ -> "."

{- | The default cache path for a CLI named @name@:
@$XDG_CACHE_HOME/<name>/update-check.json@ (with the standard XDG
fallback to @~/.cache/<name>/update-check.json@).
-}
defaultCachePath :: Text -> IO FilePath
defaultCachePath name = do
    base <- getXdgDirectory XdgCache (T.unpack name)
    pure (base </> "update-check.json")
