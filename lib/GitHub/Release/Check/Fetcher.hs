{- |
Module      : GitHub.Release.Check.Fetcher
Description : HTTP fetcher for the GitHub Releases API
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

The default 'Fetcher' is a thin wrapper around @http-client-tls@ that
calls @/repos/:owner/:repo/releases/latest@, parses the @tag_name@,
strips a leading @v@, and returns a 'Version'. Any failure — network
error, non-200 response, parse failure, or timeout — collapses to
'Nothing' so the update check stays silent on errors.

Test code can substitute its own 'Fetcher' to drive the IO entry
point without touching the network.
-}
module GitHub.Release.Check.Fetcher
    ( RepoSlug (..)
    , Fetcher
    , httpFetcher
    , parseTagName
    ) where

import Control.Exception (SomeException, try)
import Data.Aeson (Value (..), eitherDecodeStrict', (.:))
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as BSL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Version (Version, parseVersion)
import Network.HTTP.Client
    ( Request (..)
    , httpLbs
    , parseRequest
    , requestHeaders
    , responseBody
    , responseStatus
    , responseTimeoutMicro
    )
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types.Status (statusIsSuccessful)
import Text.ParserCombinators.ReadP (readP_to_S)

-- | A GitHub repository identifier (owner, name).
data RepoSlug = RepoSlug
    { rsOwner :: !Text
    , rsName :: !Text
    }
    deriving stock (Show, Eq)

{- | The fetcher contract. The first argument is the timeout in
microseconds; 'Nothing' is returned on any failure so the caller does
not have to distinguish kinds of errors.
-}
type Fetcher = Int -> RepoSlug -> IO (Maybe Version)

{- | The default HTTPS fetcher. Builds a fresh TLS 'Manager' per call
— update checks are rare enough that the per-call cost is negligible
and it removes a global resource from the library surface.

The fetcher is exception-safe: every error path returns 'Nothing'.
-}
httpFetcher :: Fetcher
httpFetcher timeoutMicros (RepoSlug owner name) = do
    e <- try @SomeException $ do
        mgr <- newTlsManager
        req <- mkRequest owner name timeoutMicros
        resp <- httpLbs req mgr
        if statusIsSuccessful (responseStatus resp)
            then case eitherDecodeStrict' (BSL.toStrict (responseBody resp)) of
                Right v -> pure (parseTag v)
                Left _ -> pure Nothing
            else pure Nothing
    pure $ case e of
        Left _ -> Nothing
        Right v -> v

mkRequest :: Text -> Text -> Int -> IO Request
mkRequest owner name timeoutMicros = do
    let url =
            "https://api.github.com/repos/"
                <> T.unpack owner
                <> "/"
                <> T.unpack name
                <> "/releases/latest"
    base <- parseRequest url
    pure
        base
            { requestHeaders =
                [ ("User-Agent", "github-release-check (hs)")
                , ("Accept", "application/vnd.github+json")
                , ("X-GitHub-Api-Version", "2022-11-28")
                ]
            , responseTimeout = responseTimeoutMicro timeoutMicros
            }

parseTag :: Value -> Maybe Version
parseTag v = case parseEither (.: "tag_name") =<< asObject v of
    Left _ -> Nothing
    Right t -> parseTagName t
  where
    asObject (Object o) = Right o
    asObject _ = Left "expected JSON object"

{- | Parse a GitHub tag name into a 'Version'. Accepts both @v0.1.2@
and @0.1.2@ shapes. Returns 'Nothing' on anything 'Data.Version'
cannot parse cleanly.
-}
parseTagName :: Text -> Maybe Version
parseTagName tag =
    let stripped =
            case T.uncons (T.strip tag) of
                Just ('v', rest) -> rest
                Just ('V', rest) -> rest
                _ -> T.strip tag
    in  case [v | (v, "") <- readP_to_S parseVersion (T.unpack stripped)] of
            (v : _) -> Just v
            [] -> Nothing
