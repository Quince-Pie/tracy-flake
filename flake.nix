{
  description = "Tracy, a real-time, nanosecond resolution frame profiler";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      # Nixpkgs 26.05 deprecates x86_64-darwin; the overlay still serves it.
      forAllSystems = f: {
        x86_64-linux = f nixpkgs.legacyPackages.x86_64-linux;
        aarch64-linux = f nixpkgs.legacyPackages.aarch64-linux;
        aarch64-darwin = f nixpkgs.legacyPackages.aarch64-darwin;
      };
    in
    {
      overlays.default = final: _prev: {
        tracy = final.callPackage ./package.nix { };
      };

      packages = forAllSystems (
        pkgs:
        let
          # Shared with consumers that follow this nixpkgs, unlike a private import.
          tracy = pkgs.callPackage ./package.nix { };
        in
        {
          default = tracy;
          inherit tracy;
          tracy-client = tracy.client;
          tracy-tools = tracy.tools;
        }
      );

      checks = forAllSystems (
        pkgs:
        let
          inherit (pkgs.stdenv.hostPlatform) system;
          packages = removeAttrs self.packages.${system} [ "default" ];
          testChecks = builtins.listToAttrs (
            builtins.concatMap (
              name:
              let
                inherit (packages.${name}) tests;
              in
              map (test: {
                name = "${name}-tests-${test}";
                value = tests.${test};
              }) (builtins.attrNames tests)
            ) (builtins.attrNames packages)
          );
        in
        packages
        // testChecks
        // {
          formatting =
            pkgs.runCommandLocal "tracy-formatting" { nativeBuildInputs = [ self.formatter.${system} ]; }
              ''
                cp -R --no-preserve=mode ${self} source
                treefmt --ci --working-dir source
                touch "$out"
              '';
        }
      );

      formatter = forAllSystems (
        pkgs:
        pkgs.nixfmt-tree.override {
          # Outside a repository, treefmt would otherwise walk the store.
          settings.tree-root-file = "flake.nix";
        }
      );
    };
}
