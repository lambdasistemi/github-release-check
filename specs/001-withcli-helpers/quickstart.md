# Quickstart — Adopting `withCli` + `versionOption`

This walks through what a consumer Haskell CLI does to switch from
the legacy 8-line stanza to the bundled one-liner, and how to add a
consistent `--version` flag.

## 1. Bump the pin

Update the `github-release-check` pin to the post-feature commit
(once merged). No change in core `build-depends` is needed for
consumers who only adopt `withCli`.

For consumers who also want `--version`, add the sublibrary to their
own `build-depends`:

```cabal
build-depends:
  , github-release-check
  , github-release-check:optparse        -- only if you want versionOption
  , optparse-applicative                 -- you almost certainly already have this
```

## 2. Replace the 8-line stanza with one call

**Before:**

```haskell
main :: IO ()
main = do
    cfg <- updateCheckConfig
    withUpdateCheck cfg $ do
        argv <- getArgs
        options <- parseArgs version argv
        run options

updateCheckConfig :: IO Config
updateCheckConfig = do
    disabled <- isJust <$> lookupEnv "MY_CLI_NO_UPDATE_CHECK"
    base <- defaultConfig (RepoSlug "lambdasistemi" "my-cli") "my-cli" version
    pure base { cfgDisabled = disabled }
```

**After:**

```haskell
import GitHub.Release.Check         -- exports CliBanner + withCli
import Paths_my_cli (version)

main :: IO ()
main = withCli banner id $ do
    argv <- getArgs
    options <- parseArgs version argv
    run options

banner :: CliBanner
banner = CliBanner
    { cliRepo         = RepoSlug "lambdasistemi" "my-cli"
    , cliExe          = "my-cli"
    , cliVersion      = version
    , cliOptOutEnvVar = "MY_CLI_NO_UPDATE_CHECK"
    }
```

Notes:

- The opt-out env-var name stays caller-supplied. The convention is
  `<UPPER_SNAKE_EXE_NAME>_NO_UPDATE_CHECK`.
- The `id` is the modifier — pass `id` when you want all `defaultConfig`
  defaults. The next section shows when you'd pass something else.

## 3. Override `Config` fields without losing the one-liner

If you need a non-default field (custom cache path, alternate print
sink, longer check interval, …), pass a modifier:

```haskell
main :: IO ()
main =
    withCli banner
        (\cfg -> cfg
            { cfgCheckInterval = 24 * 3600    -- check once a day instead of hourly
            , cfgPrint         = T.IO.putStrLn  -- banner to stdout, not stderr
            })
        $ do
            ...
```

The env-var kill switch (`MY_CLI_NO_UPDATE_CHECK=1`) **takes
precedence** over your modifier: setting the env var disables the
check even if your modifier sets `cfgDisabled = False`. This is
deliberate (FR-002) so a careless modifier cannot silently defeat
the user's opt-out.

## 4. Add a consistent `--version` flag

Add `github-release-check:optparse` to your `build-depends` and plumb
`versionOption` into your `optparse-applicative` parser:

```haskell
import Options.Applicative
import GitHub.Release.Check.OptParse (versionOption)

main :: IO ()
main = do
    opts <- execParser $
        info
            (myOptionsParser <**> versionOption banner <**> helper)
            (fullDesc <> progDesc "...")
    withCli banner id (run opts)
```

`my-cli --version` now prints `my-cli <semver>` on one line and exits
`0`, with the exe name and version drawn from the same `banner`
record `withCli` uses (no duplication).

## 5. Verify

After the migration:

```bash
# Normal invocation still works:
my-cli some-subcommand --some-arg

# Env opt-out skips the update check:
MY_CLI_NO_UPDATE_CHECK=1 my-cli some-subcommand --some-arg

# --version short-circuits:
my-cli --version   # prints "my-cli 0.3.7" (or whatever Paths_my_cli.version is), exits 0
```

The library's existing semantics (silent on network failure, banner-on-exit, on-disk cache rate-limiting) are preserved verbatim.

## 6. In-repo reference

The `github-release-check-canary` executable in this repository is
the in-repo dogfood site for both helpers. Read `app/canary/Main.hs`
for a working ~10-line example.
