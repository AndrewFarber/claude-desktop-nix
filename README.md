# claude-desktop-nix

[![build](https://github.com/AndrewFarber/claude-desktop-nix/actions/workflows/build.yml/badge.svg)](https://github.com/AndrewFarber/claude-desktop-nix/actions/workflows/build.yml)

Nix flake that packages Anthropic's official Claude Desktop Linux build
(the `.deb` from `downloads.claude.ai`) for NixOS. The binary is fetched
directly from Anthropic; this repo contains no redistributed binaries.

Supports `x86_64-linux` and `aarch64-linux`. The package is unfree.

> [!NOTE]
> This is an unofficial community packaging, not affiliated with or endorsed
> by Anthropic.

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

## Claude Code

The app downloads its own Claude Code CLI into `~/.config/Claude/claude-code/`
at runtime. That's a generic glibc binary whose ELF interpreter is
`/lib64/ld-linux-*.so`, which NixOS doesn't provide (`Could not start
dynamically linked executable`).

The build patches `app.asar` so that once a download passes its checksum
(and before the file is moved into place), the app sets the binary's
interpreter to the Nix glibc loader with `patchelf`. Binaries downloaded
before this fix get patched the next time the app checks them. The app still
picks, downloads and updates the CLI version itself, and the CLI runs
directly on the host, so `sudo`, `/etc` and your environment behave normally.
Only the local CLI is changed: the copies the app sends to SSH hosts and to
the Cowork VM keep their original interpreter. The build fails loudly if a
release moves the code these hooks attach to.

See [`claude-code-interpreter.js`](claude-code-interpreter.js).

## Cowork VM

The app hardcodes Debian paths for qemu, OVMF/AAVMF firmware and virtiofsd.
The build rewrites those paths in `app.asar` to Nix store paths. The build
fails loudly if a new release moves them.

At runtime Cowork also needs read/write access to `/dev/kvm` and
`/dev/vhost-vsock`. If they're not world-writable on your system, add your
user to the `kvm` group.

The qemu dependency makes the closure large (~2.3 GB, ~1.5 GB without
Cowork). If you don't use Cowork, build without it:

```nix
inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.default.override { withCowork = false; }
# or, with the overlay
pkgs.claude-desktop.override { withCowork = false; }
```

## Updates

`.github/workflows/update.yml` runs daily:

1. `.github/update-sources.sh` verifies the apt repo's `InRelease` against the
   pinned key in `keys/`, checks each `Packages` index against the signed
   `Release`, and writes the newest version and `.deb` hash to `sources.json`.
   It refuses an expired `Release` (`Valid-Until`, which guards against a
   replayed old index), a version older than the one already pinned, and
   architectures that disagree on the version.
2. If anything changed, both architectures are built (`build.yml`).
3. Only if both builds pass, the new `sources.json` is committed to `main`.

`.github/workflows/update-lock.yml` does the same weekly for `flake.lock`, so
the nixpkgs libraries the app links against get security fixes.

To update locally instead: `just update && just build`.

The workflows run with read-only tokens. Only the final commit jobs get
`contents: write`, and every action is pinned to a commit SHA (Dependabot
proposes bumps). Those commit jobs push straight to `main`, so branch
protection on `main` must allow `github-actions[bot]` to push.

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
  uses the unprivileged user-namespace sandbox instead, so the app won't start
  with `security.allowUserNamespaces = false` (e.g. some hardened profiles).
- The GNOME Shell search provider isn't installed (its D-Bus service
  hardcodes `/usr` paths). Nor are the `.deb`'s apt repo and AppArmor profile,
  which don't apply on NixOS. File associations for `.mcpb`, `.dxt` and
  `.skill` and the `ccd` launcher (when a release ships it) are installed.
- In-app auto-update doesn't apply; update via this flake.
- If Anthropic rotates the signing key, replace `keys/claude-desktop.asc`
  after checking the new fingerprint.

## License

The packaging code in this repository (Nix expressions, scripts and
workflows) is released under the [MIT License](LICENSE). It does not cover
Claude Desktop itself, which is proprietary software owned by Anthropic and
downloaded from Anthropic at build time under
[Anthropic's terms](https://www.anthropic.com/legal).
