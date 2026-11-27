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
inputs.claude-desktop.url = "github:AndrewFarber/claude-desktop-nix";

# then either
home.packages = [ inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.default ];
# or
nixpkgs.overlays = [ inputs.claude-desktop.overlays.default ];  # -> pkgs.claude-desktop
```

The overlay requires `nixpkgs.config.allowUnfree = true`.

`packages` is built against this flake's locked nixpkgs (`nixos-unstable`).
To share your own nixpkgs and avoid a second copy of its libraries, add
`inputs.claude-desktop.inputs.nixpkgs.follows = "nixpkgs";` or use the
overlay.

## Wayland

Set `NIXOS_OZONE_WL=1` (e.g. `environment.sessionVariables`) to run natively
on Wayland instead of XWayland.

## Claude Code

Upstream, the app downloads its own Claude Code CLI into
`~/.config/Claude/claude-code/` at runtime and keeps updating it. Here the CLI
comes from the Nix store instead, so it's reproducible and pinned with the app:

- Each app release names the exact CLI build it runs (version and sha256) in a
  manifest inside `app.asar`. `update-sources.sh` copies that pin from the
  verified `.deb` into `sources.json`, and the build fetches that file and
  fails if the pin no longer matches the app's manifest.
- The host copy gets its ELF interpreter pointed at the Nix glibc loader. The
  upstream binary expects `/lib64/ld-linux-*.so`, which NixOS doesn't provide.
- The build sets the app's dormant local-override path to the store copy.
  That turns off downloading, auto-updating, repairing and cleaning up the
  CLI. The override reports the pinned version, so version-gated features
  still see the real version. The CLI runs directly on the host, so `sudo`,
  `/etc` and your environment behave normally.
- With Cowork, the VM gets an unmodified store copy, since the Nix loader
  doesn't exist inside it. The app copies it into
  `~/.config/Claude/claude-code-vm/local/` when a VM starts.

The CLI only changes when the app does: a newer CLI that Anthropic publishes
between Desktop releases isn't picked up. The CLI copies sent to SSH hosts are
still downloaded by the app, since they run on the remote machine.

Older versions of this package (and plain upstream) left downloads in
`~/.config/Claude/claude-code/`. Nothing uses them any more, and you can
delete that directory.

## PATH

At startup the app replaces `PATH` with a fixed list of root-owned system
directories, as hardening against `PATH` hijacking. On NixOS that hides
per-user packages (`users.users.<name>.packages`, Home Manager with
`useUserPackages`), so for example links and sign-in buttons can't open a
browser installed there. The build appends `/etc/profiles/per-user/$USER/bin`
and the store paths of the tools the app needs (bubblewrap, openssh, socat,
xdg-utils). Only root can change either. The app adds its base list to `PATH`
without checking it (its root-owned check only filters `/usr/local`), so
user-writable profiles such as `~/.nix-profile/bin` are deliberately not
added: that would undo the hardening.

Two tools are called by absolute Debian path rather than through `PATH`: the
system SSH client (`/usr/bin/ssh`, plus `ssh-add` next to it) and
`/usr/bin/secret-tool`, which reads the browser key when importing cookies.
The build points both at store copies. KDE Wallet's `kwallet-query` isn't
patched, so cookie import from browsers that keep their key in KWallet
doesn't work.

## Cowork VM

The app hardcodes Debian paths for qemu, OVMF/AAVMF firmware and virtiofsd.
The build rewrites those paths in `app.asar` to Nix store paths. The build
fails loudly if a new release moves them.

At runtime Cowork also needs read/write access to `/dev/kvm` and
`/dev/vhost-vsock`. If they're not world-writable on your system, add your
user to the `kvm` group.

The qemu dependency and the second, unmodified CLI copy make the closure large
(~3.2 GB, ~2.0 GB without Cowork). If you don't use Cowork, build without it:

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
   For a new `.deb` it also downloads it, checks its hash, and copies the
   Claude Code CLI pin from the app's manifest. It refuses an expired
   `Release` (`Valid-Until`, which guards against a replayed old index), a
   version older than the one already pinned, and architectures that disagree
   on the app or CLI version.
2. If anything changed, both architectures are built (`build.yml`).
3. Only if both builds pass, the new `sources.json` is committed to `main`. If
   `main` moved while the candidate was building, the commit is skipped. That
   combination was never built, and the next run retries against the new
   `main`.

`.github/workflows/update-lock.yml` does the same weekly with
`nix flake update` for `flake.lock`, so the nixpkgs libraries the app links against
get security fixes.

To update locally instead: `just update` (app and CLI) or `just update-lock`
(nixpkgs), then `just build`.

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

The dev shell provides `just`, the lint tools, and `curl`/`gpg`/`jq`/`dpkg`
for the update script (CI runs it in the same shell). The repo ships an
`.envrc` (`use flake`), so with
[direnv](https://direnv.net) and nix-direnv the shell loads automatically on
`cd`. Without direnv, enter it with `nix develop` or prefix commands with
`nix develop -c` (e.g. `nix develop -c just update`).

`just` lists the recipes: `lint`, `fmt`, `check`, `build`, `run`, `update`,
`update-lock`.

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
- In-app auto-update doesn't apply, for the app or its Claude Code CLI; update
  via this flake.
- If Anthropic rotates the signing key, replace `keys/claude-desktop.asc`
  after checking the new fingerprint. The pinned key is
  `31DD DE24 DDFA B679 F42D  7BD2 BAA9 29FF 1A7E CACE`
  (Anthropic Claude Code Release Signing, created 2026-03-30).
- Upstream, an app release could pin a separate desktop build of the Claude
  Code CLI (`desktopManifest`). Neither `update-sources.sh` nor the build
  handles that yet, so both fail on such a release instead of pinning the
  wrong CLI.

## License

The packaging code in this repository (Nix expressions, scripts and
workflows) is released under the [MIT License](LICENSE). It does not cover
Claude Desktop itself, which is proprietary software owned by Anthropic and
downloaded from Anthropic at build time under
[Anthropic's terms](https://www.anthropic.com/legal).
