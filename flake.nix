{
  description = "Claude Desktop (official Linux build) packaged for Nix";

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

      overlays.default = final: _prev: {
        claude-desktop = final.callPackage ./package.nix { };
      };

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
