{- |
Module      : Main
Description : github-release-check-canary — dogfood the library
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

A tiny executable that runs the @github-release-check@ library against
this very repository. The point is integration coverage:

* every build exercises the full IO path (cache file, HTTP fetcher,
  decision rules, banner sink);
* on every CI run, a regression in any of those layers fails here
  before downstream consumers can pull a broken pin;
* operators can invoke @nix run .#canary@ as a one-shot probe.

The canary prints a single line and exits 0. If the live
@releases\/latest@ for this repository reports a tag higher than the
locally-built version, the library prints the banner to stderr
after the action returns; otherwise nothing extra appears.
-}
module Main (main) where

import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Version (showVersion)
import System.Environment (lookupEnv)

import GitHub.Release.Check
    ( RepoSlug (..)
    , cfgDisabled
    , defaultConfig
    , withUpdateCheck
    )

import Paths_github_release_check (version)

owner, repo, exeName :: T.Text
owner = "lambdasistemi"
repo = "github-release-check"
exeName = "github-release-check-canary"

main :: IO ()
main = do
    disabled <-
        isJust
            <$> lookupEnv
                "GITHUB_RELEASE_CHECK_CANARY_NO_UPDATE_CHECK"
    cfg <-
        defaultConfig
            (RepoSlug owner repo)
            exeName
            version
    withUpdateCheck cfg{cfgDisabled = disabled} $
        putStrLn $
            T.unpack exeName
                <> " "
                <> showVersion version
                <> " — library wired against "
                <> T.unpack owner
                <> "/"
                <> T.unpack repo
