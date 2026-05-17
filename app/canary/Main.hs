{- |
Module      : Main
Description : github-release-check-canary — dogfood the library
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

A tiny executable that runs the github-release-check library against
this very repository. Dogfoods withCli + versionOption end-to-end and
serves as the in-repo proof site for both helpers.
-}
module Main (main) where

import Data.Text qualified as T
import Data.Version (showVersion)
import Options.Applicative
    ( execParser
    , fullDesc
    , helper
    , info
    , (<**>)
    )

import GitHub.Release.Check
    ( CliBanner (..)
    , RepoSlug (..)
    , withCli
    )
import GitHub.Release.Check.OptParse (versionOption)

import Paths_github_release_check (version)

banner :: CliBanner
banner =
    CliBanner
        { cliRepo =
            RepoSlug "lambdasistemi" "github-release-check"
        , cliExe = "github-release-check-canary"
        , cliVersion = version
        , cliOptOutEnvVar =
            "GITHUB_RELEASE_CHECK_CANARY_NO_UPDATE_CHECK"
        }

main :: IO ()
main = do
    () <-
        execParser
            ( info
                (pure () <**> versionOption banner <**> helper)
                fullDesc
            )
    withCli banner id $
        putStrLn $
            T.unpack (cliExe banner)
                <> " "
                <> showVersion (cliVersion banner)
                <> " — library wired against "
                <> T.unpack (rsOwner (cliRepo banner))
                <> "/"
                <> T.unpack (rsName (cliRepo banner))
