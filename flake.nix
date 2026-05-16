{
  description =
    "github-release-check: print an update banner when a CLI is behind its latest GitHub release";

  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
  };

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    lintNixpkgs.url =
      "github:NixOS/nixpkgs/647e5c14cbd5067f44ac86b74f014962df460840";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, lintNixpkgs, flake-parts, haskellNix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      perSystem = { system, ... }:
        let
          pkgs = import nixpkgs {
            overlays = [ haskellNix.overlay ];
            inherit system;
          };
          lintPkgs = import lintNixpkgs { inherit system; };
          indexState = "2026-02-17T10:15:41Z";

          project = import ./nix/project.nix {
            inherit pkgs indexState lintPkgs;
            src = ./.;
          };
          components = project.hsPkgs.github-release-check.components;
          checks = import ./nix/checks.nix {
            inherit pkgs components lintPkgs;
            src = ./.;
          };
          checkApps = import ./nix/apps.nix { inherit pkgs checks; };
          publicChecks = builtins.removeAttrs checks [ "apps" ];
        in {
          packages = {
            default = components.library;
            inherit (components) library;
            unit-tests = components.tests.unit-tests;
            canary =
              components.exes.github-release-check-canary;
          };
          checks = publicChecks;
          apps = checkApps // {
            canary = {
              type = "app";
              program = "${
                  components.exes.github-release-check-canary
                }/bin/github-release-check-canary";
            };
          };
          devShells.default = project.shell;
        };
    };
}
