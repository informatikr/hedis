{
  description = "Haskell Redis client library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        hpkgs = pkgs.haskellPackages;
      in {
        packages.default = hpkgs.developPackage { root = ./.; };

        devShells.default = hpkgs.developPackage {
          root = ./.;
          returnShellEnv = true;
          modifier = drv:
            pkgs.haskell.lib.addBuildTools drv [
              hpkgs.cabal-install
              pkgs.redis
            ];
        };
      });
}
