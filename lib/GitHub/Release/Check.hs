{- |
Module      : GitHub.Release.Check
Description : Banner-on-exit update check for Haskell CLIs
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

The public surface of @github-release-check@.

The intended use is to wrap @main@'s body in 'withUpdateCheck':

@
import GitHub.Release.Check
import Paths_my_cli (version)

main :: IO ()
main = do
    cfg <- defaultConfig
        (RepoSlug \"owner\" \"my-cli\")
        \"my-cli\"
        version
    withUpdateCheck cfg $ do
        ...                  -- real CLI work
@

After the inner action returns — or throws — the check runs:

* if the cache is older than @cfgCheckInterval@, it fetches the
  latest release tag from the GitHub Releases API (silent on
  failure);
* if the latest known release is greater than @cfgCurrentVersion@
  and the banner has not printed within @cfgBannerInterval@, it
  emits a single-line banner via @cfgPrint@ and remembers the time.

The check never raises and never affects the wrapped action's
exit code.
-}
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
