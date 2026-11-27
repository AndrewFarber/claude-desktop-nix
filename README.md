# claude-desktop-nix

Nix flake that packages Anthropic's official Claude Desktop Linux build
(the `.deb` from `downloads.claude.ai`) for NixOS. The binary is fetched
directly from Anthropic; this repo contains no redistributed binaries.

Supports `x86_64-linux` and `aarch64-linux`. The package is unfree.

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

To update locally instead:

```sh
nix shell nixpkgs#gnupg nixpkgs#jq -c .github/update-sources.sh && nix build
```

The arm64 job uses GitHub's `ubuntu-24.04-arm` runner. If that isn't available
for your repo, drop it from the matrix in `build.yml`.

## Known limitations

- `chrome-sandbox` is removed (it can't be setuid in the Nix store); Chromium
  uses the unprivileged user-namespace sandbox instead.
- In-app auto-update doesn't apply; update via this flake.
- If Anthropic rotates the signing key, replace `keys/claude-desktop.asc`
  after checking the new fingerprint.
