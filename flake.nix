{
  description = "Tracy, a real-time, nanosecond resolution frame profiler";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      # Nixpkgs 26.05 deprecates x86_64-darwin; the overlay still serves it.
      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
    {
      overlays.default = final: _prev: {
        tracy = final.callPackage ./package.nix { };
      };

      packages = forAllSystems (
        system:
        let
          # Shared with consumers that follow this nixpkgs, unlike a private import.
          tracy = nixpkgs.legacyPackages.${system}.callPackage ./package.nix { };
        in
        {
          default = tracy;
          inherit tracy;
          tracy-client = tracy.client;
          tracy-tools = tracy.tools;
        }
      );

      checks = forAllSystems (
        system:
        let
          packages = removeAttrs self.packages.${system} [ "default" ];
        in
        packages
        // lib.concatMapAttrs (
          name: package: lib.mapAttrs' (test: lib.nameValuePair "${name}-tests-${test}") package.tests
        ) packages
        // {
          formatting =
            nixpkgs.legacyPackages.${system}.runCommandLocal "tracy-formatting"
              { nativeBuildInputs = [ self.formatter.${system} ]; }
              ''
                cp -R --no-preserve=mode ${self} source
                treefmt --ci --working-dir source
                touch "$out"
              '';
        }
      );

      formatter = forAllSystems (
        system:
        nixpkgs.legacyPackages.${system}.nixfmt-tree.override {
          # Outside a repository, treefmt would otherwise walk the store.
          settings.tree-root-file = "flake.nix";
        }
      );
    };
}
