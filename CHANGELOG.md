# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project adheres to [Haskell PVP](https://pvp.haskell.org/).

## [0.1.0.0] - Unreleased

### Added

- Initial library: `GitHub.Release.Check.withUpdateCheck` wraps an `IO`
  action and, on exit, prints a one-line banner to a caller-supplied
  sink when the GitHub Releases API reports a newer version than the
  configured current version.
- On-disk cache with two independent rate limits (one for GitHub hits,
  one for banner prints).
- `Fetcher` abstraction so tests can stub the HTTP layer.
- Silent failure on network errors / parse errors / timeouts.
