{
  description = "Claude Desktop (official Linux build) packaged for Nix";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      packages.${system} = {
        claude-desktop = pkgs.callPackage ./package.nix { };
        default = self.packages.${system}.claude-desktop;
      };

      overlays.default = final: _prev: {
        claude-desktop = final.callPackage ./package.nix { };
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
