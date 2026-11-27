{
  description = "Claude Desktop (official Linux build) packaged for Nix";

  # Consumers can set `inputs.claude-desktop.inputs.nixpkgs.follows` to build
  # `packages` against their own nixpkgs, or use the overlay.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = builtins.attrNames (builtins.fromJSON (builtins.readFile ./sources.json));
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            }
          )
        );
    in
    {
      packages = forAllSystems (pkgs: {
        claude-desktop = pkgs.callPackage ./package.nix { };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop;
      });

      # `nix flake check` builds the package for the current system.
      checks = nixpkgs.lib.genAttrs systems (system: {
        inherit (self.packages.${system}) claude-desktop;
      });

      overlays.default = final: _prev: {
        claude-desktop = final.callPackage ./package.nix { };
      };

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            # lint
            actionlint
            deadnix
            nixfmt
            shellcheck
            statix
            # tasks
            just
            # .github/update-sources.sh
            curl
            dpkg
            gnupg
            jq
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
