# github-release-check

Haskell library to check the GitHub Releases API for newer versions of
a CLI and print an update banner. Designed for small, on-prem CLIs:

- Silent on network failure (2s timeout).
- Disk-cached: hits GitHub at most once per hour per machine.
- Banner rate-limited too (default: at most one print per hour).
- Opt-out via a caller-named environment variable.
- No authenticated calls — relies on the public 60/hour rate limit.

Status: bootstrap; real implementation in flight (see open PR).
