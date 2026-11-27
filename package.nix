# Repackages Anthropic's official Linux .deb (bundled Electron) for NixOS.
# Run ./update.sh to bump version + hash from Anthropic's apt repo.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeShellWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
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
  libcap_ng,
  libseccomp,
  libuuid,
  libxkbcommon,
  libayatana-appindicator,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
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
}:

stdenv.mkDerivation rec {
  pname = "claude-desktop";
  version = "6.28899.6";

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb";
    sha256 = "7e381601d86570149643d52e9b89c26575ab12fa788aa41ffdd4cca5b0638cf8";
  };

  nativeBuildInputs = [
    dpkg
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
    # bundled virtiofsd (Cowork VM)
    libcap_ng
    libseccomp
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

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin
    cp -r usr/lib/claude-desktop $out/lib/
    cp -r usr/share $out/

    # The setuid helper can't be setuid in the store; without it Chromium
    # falls back to the user-namespace sandbox, which NixOS allows.
    rm $out/lib/claude-desktop/chrome-sandbox

    runHook postInstall
  '';

  # gappsWrapperArgs is only populated in preFixup, so wrap after it.
  postFixup = ''
    makeShellWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
  '';

  meta = {
    description = "Desktop application for Claude.ai";
    homepage = "https://claude.ai";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-desktop";
  };
}
