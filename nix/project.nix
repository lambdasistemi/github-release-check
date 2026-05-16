{ pkgs, src, indexState, lintPkgs ? pkgs, ... }:

let
  project = pkgs.haskell-nix.cabalProject' {
    name = "github-release-check";
    inherit src;
    compiler-nix-name = "ghc9123";
    shell = {
      withHoogle = true;
      tools = { cabal = { index-state = indexState; }; };
      # Lint/format tools come from a pinned nixpkgs whose GHC matches
      # the tool's base bounds. Pulling them through `tools = { }`
      # would force haskell.nix to solve them against the project's
      # GHC 9.12 (base 4.21), which Hackage's cabal-fmt/fourmolu/hlint
      # do not yet support.
      buildInputs = (with lintPkgs.haskellPackages; [
        cabal-fmt
        fourmolu
        hlint
      ]) ++ [ pkgs.just pkgs.nixfmt-classic pkgs.shellcheck ];
    };
  };
in {
  inherit project;
  inherit (project) hsPkgs shell;
}
