# claude-desktop-nix

[![build](https://github.com/AndrewFarber/claude-desktop-nix/actions/workflows/build.yml/badge.svg)](https://github.com/AndrewFarber/claude-desktop-nix/actions/workflows/build.yml)

Nix flake that packages Anthropic's official Claude Desktop Linux build
(the `.deb` from `downloads.claude.ai`) for NixOS. The binary is fetched
directly from Anthropic; this repo contains no redistributed binaries.

Supports `x86_64-linux` and `aarch64-linux`. The package is unfree.

## Try it

```sh
nix run github:AndrewFarber/claude-desktop-nix
```

## Use in a NixOS / Home Manager flake

```nix
inputs.claude-desktop = {
  url = "github:AndrewFarber/claude-desktop-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

# then either
home.packages = [ inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.default ];
# or
nixpkgs.overlays = [ inputs.claude-desktop.overlays.default ];  # -> pkgs.claude-desktop
```

The overlay requires `nixpkgs.config.allowUnfree = true`.

## Wayland

Set `NIXOS_OZONE_WL=1` (e.g. `environment.sessionVariables`) to run natively
on Wayland instead of XWayland.

## Cowork VM

The app hardcodes Debian paths for qemu, OVMF/AAVMF firmware and virtiofsd.
The build unpacks `app.asar`, rewrites those paths to Nix store paths, and
repacks it. The build fails loudly if a new release moves them.

At runtime Cowork also needs read/write access to `/dev/kvm` and
`/dev/vhost-vsock`. If they're not world-writable on your system, add your
user to the `kvm` group.

The qemu dependency makes the closure large (~2.4 GB).

## Updates

`.github/workflows/update.yml` runs daily:

1. `.github/update-sources.sh` verifies the apt repo's `InRelease` against the
   pinned key in `keys/`, checks each `Packages` index against the signed
   `Release`, and writes the newest version and `.deb` hash to `sources.json`.
2. If anything changed, both architectures are built (`build.yml`).
3. Only if both builds pass, the new `sources.json` is committed to `main`.

To update locally instead: `just update && just build`.

## Development

```sh
git clone https://github.com/AndrewFarber/claude-desktop-nix
cd claude-desktop-nix
direnv allow   # or: nix develop
```

The dev shell provides `just`, the lint tools, and `gpg`/`jq` for the update
script. The repo ships an `.envrc` (`use flake`), so with
[direnv](https://direnv.net) and nix-direnv the shell loads automatically on
`cd`. Without direnv, enter it with `nix develop` or prefix commands with
`nix develop -c` (e.g. `nix develop -c just update`).

`just` lists the recipes: `lint`, `fmt`, `check`, `build`, `run`, `update`.

The arm64 job uses GitHub's `ubuntu-24.04-arm` runner. If that isn't available
for your repo, drop it from the matrix in `build.yml`.

## Known limitations

- `chrome-sandbox` is removed (it can't be setuid in the Nix store); Chromium
  uses the unprivileged user-namespace sandbox instead.
- In-app auto-update doesn't apply; update via this flake.
- If Anthropic rotates the signing key, replace `keys/claude-desktop.asc`
  after checking the new fingerprint.
