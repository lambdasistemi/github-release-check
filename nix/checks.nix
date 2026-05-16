{ pkgs, src, components, lintPkgs ? pkgs }:

let
  scripts = {
    build = {
      runtimeInputs = [ ];
      text = ''
        test -e ${components.library}
        test -e ${components.exes.github-release-check-canary}
        echo "library + canary realized"
      '';
    };

    unit = {
      runtimeInputs = [ components.tests.unit-tests ];
      text = ''
        unit-tests
      '';
    };

    # Dogfood the library against itself. The canary exercises the
    # full IO path (cache, fetcher, decision, banner sink). The check
    # disables the actual network call via the opt-out env var so the
    # nix sandbox stays hermetic — but the IO wiring still runs and
    # any crash in the call chain fails the build.
    canary = {
      runtimeInputs = [
        components.exes.github-release-check-canary
      ];
      text = ''
        export GITHUB_RELEASE_CHECK_CANARY_NO_UPDATE_CHECK=1
        actual="$(github-release-check-canary)"
        expected_prefix="github-release-check-canary 0."
        case "$actual" in
          "$expected_prefix"*) ;;
          *)
            printf 'canary: unexpected stdout: %s\n' \
              "$actual" >&2
            exit 1
            ;;
        esac
        printf '%s\n' "$actual"
      '';
    };

    lint = {
      runtimeInputs = (with lintPkgs.haskellPackages; [
        cabal-fmt
        fourmolu
        hlint
      ]) ++ [ pkgs.diffutils pkgs.findutils ];
      text = ''
        cd ${src}
        diff -u github-release-check.cabal \
          <(cabal-fmt github-release-check.cabal)
        find . -type f -name '*.hs' \
          -not -path '*/dist-newstyle/*' \
          -exec fourmolu -m check {} +
        find . -type f -name '*.hs' \
          -not -path '*/dist-newstyle/*' \
          -exec hlint {} +
      '';
    };
  };

  mkApp = name:
    { runtimeInputs, text }:
    pkgs.writeShellApplication { inherit name runtimeInputs text; };

  mkCheck = name: spec:
    let app = mkApp name spec;
    in pkgs.runCommand name {
      nativeBuildInputs = [ pkgs.glibcLocales ];
      LANG = "C.UTF-8";
      LC_ALL = "C.UTF-8";
    } ''
      set -euo pipefail
      cd ${src}
      ${pkgs.lib.getExe app}
      touch $out
    '';

  apps = builtins.mapAttrs mkApp scripts;
in {
  build = mkCheck "build" scripts.build;
  unit = mkCheck "unit" scripts.unit;
  lint = mkCheck "lint" scripts.lint;
  canary = mkCheck "canary" scripts.canary;
  inherit apps;
}
