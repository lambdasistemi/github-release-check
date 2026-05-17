{- |
Module      : GitHub.Release.Check.OptParse
Description : optparse-applicative @--version@ helper
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

A single-purpose helper that plumbs the consumer's 'CliBanner'
into an @optparse-applicative@ @--version@ flag. Lives in its
own sublibrary so the core library stays free of any
@optparse-applicative@ dependency; consumers wiring a CLI opt
in to the dep by also depending on
@github-release-check:optparse@.

Wire into a parser via '<**>':

@
'execParser'
    (info
        (myParser '<**>' 'versionOption' banner '<**>' helper)
        idm)
@
-}
module GitHub.Release.Check.OptParse
    ( versionOption
    ) where

import Data.Text qualified as T
import Data.Version (showVersion)
import Options.Applicative
    ( Parser
    , help
    , infoOption
    , long
    )

import GitHub.Release.Check.Cli (CliBanner (..))

{- | An @optparse-applicative@ info option that prints
@"\<cliExe banner\> \<showVersion (cliVersion banner)\>"@ to
stdout and exits with 'System.Exit.ExitSuccess'. Plumb into a
consumer parser via '<**>'.
-}
versionOption :: CliBanner -> Parser (a -> a)
versionOption b =
    infoOption
        (renderVersion b)
        (long "version" <> help "Show the version and exit")

{- | Internal helper. Renders @"\<exe\> \<version\>"@ for the
printed line.
-}
renderVersion :: CliBanner -> String
renderVersion b =
    T.unpack (cliExe b) <> " " <> showVersion (cliVersion b)
