{- |
Module      : GitHub.Release.Check.Decision
Description : Pure decision logic for the update check
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Two independent gates govern the update check:

* /Fetch/ — should we hit the GitHub Releases API now, or is the
  cached result still fresh?
* /Banner/ — given the latest version we know of, should we print
  the banner now, or did we already print it recently enough?

Both gates are pure functions of @POSIXTime@ deltas. They live in
their own module so the IO entry point in
"GitHub.Release.Check" stays small and the rules can be unit-tested
exhaustively without spinning up a network stack.
-}
module GitHub.Release.Check.Decision
    ( -- * Cached state
      State (..)
    , emptyState

      -- * Decisions
    , shouldFetch
    , Banner (..)
    , decideBanner
    ) where

import Data.Time.Clock.POSIX (POSIXTime)
import Data.Version (Version)

{- | The state the cache file persists across invocations.

The three fields are independent so a failed or empty fetch does not
clobber a previously-known latest version, and a printed banner does
not bump the check timer.
-}
data State = State
    { stLastCheckEpoch :: !(Maybe POSIXTime)
    -- ^ when we last successfully hit GitHub
    , stLastKnownLatest :: !(Maybe Version)
    -- ^ the latest version GitHub reported on the last successful
    --   fetch; carried across invocations until refreshed
    , stLastBannerEpoch :: !(Maybe POSIXTime)
    -- ^ when we last printed the banner
    }
    deriving stock (Show, Eq)

-- | The all-'Nothing' state for a fresh cache.
emptyState :: State
emptyState =
    State
        { stLastCheckEpoch = Nothing
        , stLastKnownLatest = Nothing
        , stLastBannerEpoch = Nothing
        }

{- | Decide whether to hit GitHub now.

@shouldFetch interval now st@ is 'True' when the cache has no record
of a previous fetch, or when at least @interval@ seconds have passed
since the last one. @interval@ and @now@ are in epoch seconds.
-}
shouldFetch
    :: POSIXTime
    -- ^ minimum gap between fetches
    -> POSIXTime
    -- ^ current time
    -> State
    -> Bool
shouldFetch interval now st = case stLastCheckEpoch st of
    Nothing -> True
    Just t -> now - t >= interval

{- | Outcome of the banner gate. 'PrintBanner' carries the latest
version so the caller can render the message without re-reading
state.
-}
data Banner
    = NoBanner
    | PrintBanner !Version
    deriving stock (Show, Eq)

{- | Decide whether to print the banner now.

The banner prints when:

1. We know a latest version ('stLastKnownLatest' is 'Just'); and
2. That latest is strictly greater than the current version; and
3. Either we have never printed a banner, or at least
   @interval@ seconds have elapsed since the previous print.
-}
decideBanner
    :: Version
    -- ^ current (locally installed) version
    -> POSIXTime
    -- ^ minimum gap between banner prints
    -> POSIXTime
    -- ^ current time
    -> State
    -> Banner
decideBanner current interval now st = case stLastKnownLatest st of
    Nothing -> NoBanner
    Just latest
        | latest <= current -> NoBanner
        | otherwise -> case stLastBannerEpoch st of
            Nothing -> PrintBanner latest
            Just t
                | now - t >= interval -> PrintBanner latest
                | otherwise -> NoBanner
