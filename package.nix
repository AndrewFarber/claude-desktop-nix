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
  # virtiofsd (~0.8 GB of the ~2.3 GB closure) and leaves app.asar unmodified.
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
  ''
  # The fuses enable OnlyLoadAppFromAsar, so the archive must be repacked
  # rather than replaced by a plain directory.
  + lib.optionalString withCowork ''
    asar extract $res/app.asar app

    mapfile -t targets < <(grep -rlF '"/usr/bin/qemu-system-' app/.vite/build)
    if [ "''${#targets[@]}" -ne 1 ]; then
      echo "expected exactly one file defining the Cowork VM paths, found: ''${targets[*]}" >&2
      exit 1
    fi
    substituteInPlace "''${targets[0]}" ${replaceArgs}

    rm -r $res/app.asar $res/app.asar.unpacked
    # Same files Anthropic leaves unpacked: native modules and the MCP binary.
    asar pack app $res/app.asar --unpack '{*.node,github-mcp-server}'
  ''
  + ''
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
      --prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          openssh
          socat
          xdg-utils
        ]
      } \
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
