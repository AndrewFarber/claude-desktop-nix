# Repackages Anthropic's official Linux .deb (bundled Electron) for NixOS.
# Versions and hashes live in sources.json, bumped by .github/workflows/update.yml.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  asar,
  autoPatchelfHook,
  makeShellWrapper,
  patchelf,
  perl,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  bubblewrap,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libpulseaudio,
  libsecret,
  libuuid,
  libxkbcommon,
  libayatana-appindicator,
  nspr,
  nss,
  OVMF,
  openssh,
  pango,
  pipewire,
  qemu_kvm,
  socat,
  systemd,
  virtiofsd,
  vulkan-loader,
  wayland,
  xdg-utils,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxshmfence,
  libxtst,

  # Cowork runs tasks in a local qemu VM. Disabling it drops qemu, OVMF and
  # virtiofsd (~0.8 GB of the ~2.3 GB closure).
  withCowork ? true,
}:

let
  inherit (stdenv.hostPlatform) system;
  sources = lib.importJSON ./sources.json;
  source = sources.${system} or (throw "claude-desktop: unsupported system ${system}");

  # Cowork's VM backend hardcodes Debian paths; point them into the store.
  # The app derives the VARS file by swapping CODE -> VARS in the firmware
  # path, which matches the nixpkgs OVMF layout on both architectures.
  coworkPaths =
    {
      x86_64-linux = {
        "/usr/bin/qemu-system-x86_64" = "${qemu_kvm}/bin/qemu-system-x86_64";
        "/usr/share/OVMF/OVMF_CODE_4M.fd" = OVMF.firmware;
      };
      aarch64-linux = {
        "/usr/bin/qemu-system-aarch64" = "${qemu_kvm}/bin/qemu-system-aarch64";
        "/usr/share/AAVMF/AAVMF_CODE.fd" = OVMF.firmware;
      };
    }
    .${system}
    // {
      "/usr/bin/virtiofsd" = "${virtiofsd}/bin/virtiofsd";
    };

  replaceArgs = lib.concatStringsSep " " (
    lib.mapAttrsToList (
      from: to: "--replace-fail ${lib.escapeShellArg "\"${from}\""} ${lib.escapeShellArg "\"${to}\""}"
    ) coworkPaths
  );

  # Tools the app runs: bwrap for its sandbox, ssh/socat for SSH remotes,
  # xdg-open for links.
  runtimeTools = [
    bubblewrap
    openssh
    socat
    xdg-utils
  ];

  # At startup the app replaces PATH with a fixed list of root-owned system
  # dirs (hardening against PATH hijacking). On NixOS that drops per-user
  # packages (users.users.<name>.packages, Home Manager's useUserPackages),
  # so e.g. links can't open a browser installed there, and it drops the
  # tools the wrapper adds. Both are root-owned and read-only, which is the
  # app's own trust test, so append them.
  extraAppPath = lib.concatStringsSep "," (
    [
      ''...(()=>{try{return["/etc/profiles/per-user/"+require("os").userInfo().username+"/bin"]}catch{return[]}})()''
    ]
    ++ map (p: ''"${lib.getBin p}/bin"'') runtimeTools
  );
in

stdenv.mkDerivation {
  pname = "claude-desktop";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url;
    hash = "sha256:${source.sha256}";
  };

  nativeBuildInputs = [
    dpkg
    asar
    autoPatchelfHook
    makeShellWrapper
    perl
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    glib
    gsettings-desktop-schemas
    gtk3
    libdrm
    libgbm
    libnotify
    libsecret
    libuuid
    libxkbcommon
    nspr
    nss
    pango
    pipewire
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxtst
    libxcb
    libxshmfence
  ];

  # dlopen()ed by Chromium at runtime, so autoPatchelf can't see them.
  runtimeDependencies = [
    libGL
    libpulseaudio
    libayatana-appindicator
    (lib.getLib systemd)
    vulkan-loader
    wayland
  ];

  dontWrapGApps = true;

  unpackPhase = ''
    runHook preUnpack
    # Plain `dpkg-deb -x` fails: it tries to keep chrome-sandbox setuid.
    dpkg-deb --fsys-tarfile $src | tar -x --no-same-permissions --no-same-owner
    runHook postUnpack
  '';

  buildPhase = ''
    runHook preBuild

    res=usr/lib/claude-desktop/resources
    asar extract $res/app.asar app

    # Exactly one bundled file matching a fixed string, or fail the build.
    findOne() {
      mapfile -t targets < <(grep -rlF "$2" app/.vite/build)
      if [ "''${#targets[@]}" -ne 1 ]; then
        echo "expected exactly one file defining $1, found: ''${targets[*]}" >&2
        exit 1
      fi
      target=''${targets[0]}
    }
    # Apply a regex substitution that must match exactly once. REP is a Perl
    # expression (evaluated per match), so it can use $1.. and $ENV{...}.
    # The check is in END so it also fails when the file can't be opened,
    # which `perl -i` otherwise only warns about.
    replaceOnce() {
      local file=$2
      what=$1 PAT=$3 REP=$4 perl -0777 -i -pe '
        $n += s/$ENV{PAT}/$ENV{REP}/gee;
        END {
          if (($n // 0) != 1) {
            print STDERR "$ENV{what}: expected exactly one match, got " . ($n // 0) . "\n";
            $? = 1;
          }
        }
      ' "$file"
    }

    # Let the Claude Code CLI the app downloads run on NixOS; see
    # claude-code-interpreter.js. Hooks go into the CLI download path (after
    # the checksum is verified, before the binary is moved into place) and the
    # check of an existing install (fixes binaries downloaded before this).
    findOne "the Claude Code install steps" '.step="land"'
    substitute ${./claude-code-interpreter.js} interp.js \
      --subst-var-by loader ${stdenv.cc.bintools.dynamicLinker} \
      --subst-var-by patchelf ${lib.getExe patchelf}
    HELPER=$(< interp.js) replaceOnce "the bundle prologue" "$target" \
      '\A"use strict";' '"\"use strict\";$ENV{HELPER}\n"'
    replaceOnce "the Claude Code install step" "$target" \
      ',([\w$]+)\.step="land",await ([\w$]+)\(([\w$]+),([\w$]+)\)' \
      '",globalThis.__nixClaudeCodeInterpreter($3,$4),$1.step=\"land\",await $2($3,$4)"'
    replaceOnce "the Claude Code install check" "$target" \
      '([\w$]+)=this\.getBinaryPathForTarget\(([^()]*)\),await ([\w$]+)\.default\.access\(\1,([\w$]+)\.constants\.X_OK\);' \
      '"$1=this.getBinaryPathForTarget($2),await $3.default.access($1,$4.constants.X_OK);globalThis.__nixClaudeCodeInterpreter($1,$1);"'

    # Extend the app's PATH allowlist (see extraAppPath). The app keeps a copy
    # in its early bootstrap and one in the main bundle and compares the
    # resulting PATH between them, so every copy gets the same entries.
    mapfile -t targets < <(grep -rlF '"/run/current-system/profile/bin"]' app/.vite/build)
    if [ "''${#targets[@]}" -eq 0 ]; then
      echo "expected at least one file defining the app's PATH allowlist, found none" >&2
      exit 1
    fi
    for f in "''${targets[@]}"; do
      EXTRA=${lib.escapeShellArg extraAppPath} replaceOnce "the PATH allowlist in $f" "$f" \
        '"/run/current-system/profile/bin"\]' '"\"/run/current-system/profile/bin\",$ENV{EXTRA}]"'
    done
  ''
  + lib.optionalString withCowork ''
    mapfile -t targets < <(grep -rlF '"/usr/bin/qemu-system-' app/.vite/build)
    if [ "''${#targets[@]}" -ne 1 ]; then
      echo "expected exactly one file defining the Cowork VM paths, found: ''${targets[*]}" >&2
      exit 1
    fi
    substituteInPlace "''${targets[0]}" ${replaceArgs}
  ''
  # The fuses enable OnlyLoadAppFromAsar, so the archive must be repacked
  # rather than replaced by a plain directory.
  + ''
    rm -r $res/app.asar $res/app.asar.unpacked
    # Same files Anthropic leaves unpacked: native modules and the MCP binary.
    asar pack app $res/app.asar --unpack '{*.node,github-mcp-server}'

    # Only used on Ubuntu 22.04; with Cowork the patched path above is used.
    rm $res/virtiofsd $res/virtiofsd.LICENSE-*

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin
    cp -r usr/lib/claude-desktop $out/lib/
    cp -r usr/share $out/

    # The setuid helper can't be setuid in the store; without it Chromium
    # falls back to the user-namespace sandbox, which NixOS allows.
    rm $out/lib/claude-desktop/chrome-sandbox

    # What the .deb's postinst registers system-wide, minus the apt repo,
    # AppArmor profile and GNOME search provider (see README).
    res=$out/lib/claude-desktop/resources
    # File associations for .mcpb / .dxt / .skill; the desktop entry already
    # declares the MIME types.
    install -Dm644 $res/linux-mime/com.anthropic.Claude.xml \
      $out/share/mime/packages/com.anthropic.Claude.xml
    # `ccd` terminal launcher, only shipped by some releases.
    if [ -x $res/bin/ccd ]; then
      ln -s ../lib/claude-desktop/resources/bin/ccd $out/bin/ccd
    fi

    runHook postInstall
  '';

  # gappsWrapperArgs is only populated in preFixup, so wrap after it.
  postFixup = ''
    makeShellWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath runtimeTools} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
  '';

  meta = {
    description = "Desktop application for Claude.ai";
    homepage = "https://claude.ai";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.attrNames sources;
    mainProgram = "claude-desktop";
    maintainers = [
      {
        name = "Andrew Farber";
        github = "AndrewFarber";
        githubId = 6015216;
      }
    ];
  };
}
