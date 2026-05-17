module GitHub.Release.Check.OptParseSpec (spec) where

import Data.Version (makeVersion, showVersion)
import Options.Applicative
    ( ParserResult (..)
    , defaultPrefs
    , execParserPure
    , info
    , renderFailure
    , (<**>)
    )
import System.Exit (ExitCode (..))
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

import GitHub.Release.Check.Cli (CliBanner (..))
import GitHub.Release.Check.Fetcher (RepoSlug (..))
import GitHub.Release.Check.OptParse (versionOption)

banner :: CliBanner
banner =
    CliBanner
        { cliRepo = RepoSlug "owner" "exe"
        , cliExe = "exe"
        , cliVersion = makeVersion [1, 2, 3]
        , cliOptOutEnvVar = "EXE_NO_UPDATE_CHECK"
        }

expectedLine :: String
expectedLine = "exe " <> showVersion (makeVersion [1, 2, 3])

spec :: Spec
spec = do
    describe "versionOption" $ do
        it "--version prints \"<exe> <version>\" and exits success" $ do
            let pinfo =
                    info
                        (pure (42 :: Int) <**> versionOption banner)
                        mempty
            case execParserPure defaultPrefs pinfo ["--version"] of
                Failure pf -> do
                    let (rendered, code) = renderFailure pf "test"
                    code `shouldBe` ExitSuccess
                    rendered `shouldBe` expectedLine
                Success _ ->
                    fail
                        "expected Failure (info-option exit) for --version"
                CompletionInvoked _ ->
                    fail "unexpected completion"

        it "no args leaves the baseline value untouched" $ do
            let pinfo =
                    info
                        (pure (42 :: Int) <**> versionOption banner)
                        mempty
            case execParserPure defaultPrefs pinfo [] of
                Success v -> v `shouldBe` 42
                Failure _ -> fail "expected Success for empty args"
                CompletionInvoked _ ->
                    fail "unexpected completion"
