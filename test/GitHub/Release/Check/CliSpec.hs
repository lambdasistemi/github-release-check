module GitHub.Release.Check.CliSpec (spec) where

import Data.Version (makeVersion)
import System.Environment
    ( setEnv
    , unsetEnv
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

import GitHub.Release.Check
    ( CliBanner (..)
    , Config (..)
    , RepoSlug (..)
    , composeCliConfig
    )

mkBanner :: String -> CliBanner
mkBanner envVar =
    CliBanner
        { cliRepo = RepoSlug "owner" "exe"
        , cliExe = "exe"
        , cliVersion = makeVersion [0, 1, 0]
        , cliOptOutEnvVar = envVar
        }

withEnvUnset :: String -> IO a -> IO a
withEnvUnset name action = do
    unsetEnv name
    action

withEnvSet :: String -> IO a -> IO a
withEnvSet name action = do
    setEnv name "1"
    r <- action
    unsetEnv name
    pure r

spec :: Spec
spec = do
    describe "composeCliConfig — cfgDisabled truth table" $ do
        it
            "row (a): env UNSET, modifier id → cfgDisabled False"
            $ withEnvUnset "WITHCLI_TEST_OPT_OUT_A"
            $ do
                cfg <-
                    composeCliConfig
                        (mkBanner "WITHCLI_TEST_OPT_OUT_A")
                        id
                cfgDisabled cfg `shouldBe` False

        it
            "row (b): env UNSET, modifier disables → cfgDisabled True"
            $ withEnvUnset "WITHCLI_TEST_OPT_OUT_B"
            $ do
                cfg <-
                    composeCliConfig
                        (mkBanner "WITHCLI_TEST_OPT_OUT_B")
                        (\c -> c{cfgDisabled = True})
                cfgDisabled cfg `shouldBe` True

        it
            "row (c): env SET, modifier id → cfgDisabled True"
            $ withEnvSet "WITHCLI_TEST_OPT_OUT_C"
            $ do
                cfg <-
                    composeCliConfig
                        (mkBanner "WITHCLI_TEST_OPT_OUT_C")
                        id
                cfgDisabled cfg `shouldBe` True

        it
            "row (d): env SET, modifier re-enables → env wins"
            $ withEnvSet "WITHCLI_TEST_OPT_OUT_D"
            $ do
                cfg <-
                    composeCliConfig
                        (mkBanner "WITHCLI_TEST_OPT_OUT_D")
                        (\c -> c{cfgDisabled = False})
                cfgDisabled cfg `shouldBe` True

    describe "composeCliConfig — modifier overrides survive" $ do
        it
            "row (e): env UNSET, modifier sets cfgCheckInterval"
            $ withEnvUnset "WITHCLI_TEST_OPT_OUT_E"
            $ do
                cfg <-
                    composeCliConfig
                        (mkBanner "WITHCLI_TEST_OPT_OUT_E")
                        (\c -> c{cfgCheckInterval = 42})
                cfgCheckInterval cfg `shouldBe` 42

        it
            "row (f): env SET, modifier sets cfgCheckInterval"
            $ withEnvSet "WITHCLI_TEST_OPT_OUT_F"
            $ do
                cfg <-
                    composeCliConfig
                        (mkBanner "WITHCLI_TEST_OPT_OUT_F")
                        (\c -> c{cfgCheckInterval = 99})
                cfgCheckInterval cfg `shouldBe` 99
