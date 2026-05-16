{ pkgs, src, components, lintPkgs ? pkgs }:

let
  scripts = {
    build = {
      runtimeInputs = [ ];
      text = ''
        test -e ${components.library}
        echo "library realized"
      '';
    };

    unit = {
      runtimeInputs = [ components.tests.unit-tests ];
      text = ''
        unit-tests
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
  inherit apps;
}
