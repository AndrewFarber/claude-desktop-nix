# claude-desktop-nix

Nix flake that packages Anthropic's official Claude Desktop Linux build
(the `.deb` from `downloads.claude.ai`) for NixOS. The binary is fetched
directly from Anthropic; this repo contains no redistributed binaries.

x86_64-linux only. The package is unfree.

## Try it

```sh
nix run github:<you>/claude-desktop-nix
```

## Use in a NixOS / Home Manager flake

```nix
inputs.claude-desktop = {
  url = "github:<you>/claude-desktop-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

# then either
home.packages = [ inputs.claude-desktop.packages.${pkgs.system}.default ];
# or
nixpkgs.overlays = [ inputs.claude-desktop.overlays.default ];  # -> pkgs.claude-desktop
```

The overlay requires `nixpkgs.config.allowUnfree = true`.

## Wayland

Set `NIXOS_OZONE_WL=1` (e.g. `environment.sessionVariables`) to run natively
on Wayland instead of XWayland.

## Updating

```sh
./update.sh && nix build
```

`update.sh` reads Anthropic's apt index and rewrites `version` and `sha256`
in `package.nix`.

## Known limitations

- `chrome-sandbox` is removed (it can't be setuid in the Nix store); Chromium
  uses the unprivileged user-namespace sandbox instead.
- Cowork's VM mode expects `qemu-system-x86_64`, OVMF and `virtiofsd` at
  Debian paths under `/usr`, so it is unlikely to work.
- In-app auto-update doesn't apply; update via this flake.
