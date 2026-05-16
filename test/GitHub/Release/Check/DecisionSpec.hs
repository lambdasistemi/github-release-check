module GitHub.Release.Check.DecisionSpec (spec) where

import Data.Time.Clock.POSIX (POSIXTime)
import Data.Version (Version, makeVersion)
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )
import Test.QuickCheck
    ( Positive (..)
    , property
    , (.&&.)
    , (===)
    )

import GitHub.Release.Check.Decision
    ( Banner (..)
    , State (..)
    , decideBanner
    , emptyState
    , shouldFetch
    )

interval :: POSIXTime
interval = 3600

v1, v2 :: Version
v1 = makeVersion [0, 1, 0, 0]
v2 = makeVersion [0, 2, 0, 0]

spec :: Spec
spec = do
    describe "shouldFetch" $ do
        it "fires when the cache has no record" $
            shouldFetch interval 1000 emptyState `shouldBe` True

        it "fires exactly at the interval boundary" $
            shouldFetch
                interval
                (3600 + 100)
                emptyState{stLastCheckEpoch = Just 100}
                `shouldBe` True

        it "stays silent before the interval has elapsed" $
            shouldFetch
                interval
                (interval - 1)
                emptyState{stLastCheckEpoch = Just 0}
                `shouldBe` False

        it "monotonic in now: once it fires it stays firing" $
            property $
                \(Positive (i :: Integer))
                 (Positive (t0i :: Integer))
                 (Positive (deltai :: Integer)) ->
                        let iv = fromInteger i :: POSIXTime
                            t0 = fromInteger t0i :: POSIXTime
                            delta = fromInteger deltai :: POSIXTime
                            st =
                                emptyState
                                    { stLastCheckEpoch = Just t0
                                    }
                            a = shouldFetch iv (t0 + iv + delta) st
                            b = shouldFetch iv (t0 + iv + delta + 1) st
                        in  (a === True) .&&. (b === True)

    describe "decideBanner" $ do
        it "no banner when nothing is known yet" $
            decideBanner v1 interval 1000 emptyState `shouldBe` NoBanner

        it "no banner when latest == current" $
            decideBanner
                v1
                interval
                1000
                emptyState{stLastKnownLatest = Just v1}
                `shouldBe` NoBanner

        it "no banner when latest < current" $
            decideBanner
                v2
                interval
                1000
                emptyState{stLastKnownLatest = Just v1}
                `shouldBe` NoBanner

        it "prints when latest > current and never banner'd" $
            decideBanner
                v1
                interval
                1000
                emptyState{stLastKnownLatest = Just v2}
                `shouldBe` PrintBanner v2

        it "skips when within the banner interval window" $
            decideBanner
                v1
                interval
                (interval - 1)
                ( emptyState
                    { stLastKnownLatest = Just v2
                    , stLastBannerEpoch = Just 0
                    }
                )
                `shouldBe` NoBanner

        it "re-prints once the banner interval has elapsed" $
            decideBanner
                v1
                interval
                interval
                ( emptyState
                    { stLastKnownLatest = Just v2
                    , stLastBannerEpoch = Just 0
                    }
                )
                `shouldBe` PrintBanner v2

        it "current == latest never prints, regardless of timing" $
            property $
                \(t :: Integer) (tb :: Integer) ->
                    decideBanner
                        v1
                        interval
                        (fromInteger t)
                        ( emptyState
                            { stLastKnownLatest = Just v1
                            , stLastBannerEpoch = Just (fromInteger tb)
                            }
                        )
                        === NoBanner
