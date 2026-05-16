module GitHub.Release.Check.CacheSpec (spec) where

import Data.Version (makeVersion)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

import GitHub.Release.Check.Cache
    ( readState
    , writeState
    )
import GitHub.Release.Check.Decision
    ( State (..)
    , emptyState
    )

spec :: Spec
spec = do
    describe "writeState / readState" $ do
        it "roundtrips a fully-populated state" $
            withSystemTempDirectory "grc-cache" $ \dir -> do
                let path = dir </> "x" </> "update-check.json"
                let st =
                        State
                            { stLastCheckEpoch = Just 1700000000
                            , stLastKnownLatest =
                                Just (makeVersion [0, 1, 2, 3])
                            , stLastBannerEpoch = Just 1700000100
                            }
                writeState path st
                got <- readState path
                got `shouldBe` st

        it "roundtrips a partially-populated state" $
            withSystemTempDirectory "grc-cache" $ \dir -> do
                let path = dir </> "update-check.json"
                let st =
                        emptyState
                            { stLastCheckEpoch = Just 42
                            }
                writeState path st
                got <- readState path
                got `shouldBe` st

    describe "readState" $ do
        it "returns emptyState when the file does not exist" $
            withSystemTempDirectory "grc-cache" $ \dir -> do
                got <- readState (dir </> "missing.json")
                got `shouldBe` emptyState

        it "returns emptyState when the file is garbage" $
            withSystemTempDirectory "grc-cache" $ \dir -> do
                let path = dir </> "garbage.json"
                writeFile path "not json {"
                got <- readState path
                got `shouldBe` emptyState
