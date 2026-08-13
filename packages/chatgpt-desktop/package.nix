{
  alsa-lib,
  at-spi2-core,
  buildFHSEnv,
  cairo,
  cups,
  dbus,
  dpkg,
  expat,
  fetchurl,
  fontconfig,
  freetype,
  gdk-pixbuf,
  git,
  glib,
  gtk3,
  lib,
  libGL,
  libX11,
  libXScrnSaver,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXi,
  libXinerama,
  libXrandr,
  libXrender,
  libXtst,
  libdrm,
  libgbm,
  libnotify,
  libpulseaudio,
  libusb1,
  libxcb,
  libxkbcommon,
  nspr,
  nss,
  pango,
  stdenvNoCC,
  systemd,
  wayland,
  xdg-utils,
  xz,
  enableComputerUseUi ? false,
  linuxFeatureIds ? [ ],
  linuxFeaturesConfigOverride ? null,
}:

let
  source = import ./source.nix;
  system = stdenvNoCC.hostPlatform.system;
  sourceSpec =
    let
      spec = lib.attrByPath [ system ] null source.sources;
    in
    if spec == null then
      throw "NixSlop's official ChatGPT Desktop package does not support ${system}"
    else
      spec;

  contents = stdenvNoCC.mkDerivation {
    pname = "chatgpt-desktop-contents";
    inherit (source) version;
    src = fetchurl {
      inherit (sourceSpec) hash url;
    };
    nativeBuildInputs = [ dpkg ];
    dontUnpack = true;
    # Keep OpenAI's bundled ELF files, Node modules, and helper scripts
    # byte-for-byte intact. The FHS wrapper supplies their runtime libraries;
    # Nix's generic fixup pass must not rewrite vendor binaries in place.
    dontFixup = true;
    installPhase = ''
      dpkg-deb --extract "$src" "$out"
    '';
  };
in
buildFHSEnv {
  pname = "chatgpt-desktop";
  inherit (source) version;
  executableName = "chatgpt";
  runScript = "/usr/lib/chatgpt/ChatGPT";

  targetPkgs = pkgs: [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    git
    glib
    gtk3
    libGL
    libX11
    libXScrnSaver
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXi
    libXinerama
    libXrandr
    libXrender
    libXtst
    libdrm
    libgbm
    libnotify
    libpulseaudio
    libusb1
    libxcb
    libxkbcommon
    nspr
    nss
    pango
    systemd
    wayland
    xdg-utils
    xz
  ];

  extraInstallCommands = ''
    install -d "$out/usr/lib" "$out/share/applications"
    cp -a ${contents}/usr/lib/chatgpt "$out/usr/lib/"

    if [ -d ${contents}/usr/share/icons ]; then
      cp -a ${contents}/usr/share/icons "$out/share/"
    fi

    install -Dm0644 \
      ${contents}/usr/share/applications/chatgpt.desktop \
      "$out/share/applications/chatgpt.desktop"
    substituteInPlace "$out/share/applications/chatgpt.desktop" \
      --replace-fail 'Exec=chatgpt %U' "Exec=$out/bin/chatgpt %U"

    # Keep the historical launcher name as a compatibility alias. The
    # official application is the unified ChatGPT/Codex desktop app.
    ln -s chatgpt "$out/bin/codex-desktop"
  '';

  passthru = {
    inherit contents sourceSpec;
    inherit enableComputerUseUi linuxFeatureIds linuxFeaturesConfigOverride;
  };

  meta = {
    description = "Official ChatGPT desktop application for Linux, including Codex";
    homepage = "https://developers.openai.com/codex/app";
    license = lib.licenses.unfree;
    mainProgram = "chatgpt";
    platforms = builtins.attrNames source.sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
