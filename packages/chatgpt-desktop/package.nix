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
  makeWrapper,
  nspr,
  nss,
  patch,
  pango,
  runCommandLocal,
  rustPlatform,
  stdenvNoCC,
  systemd,
  symlinkJoin,
  wayland,
  xdg-utils,
  xz,
  codex-desktop-linux,
  grim,
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

  officialPackage = buildFHSEnv {
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

    # The application is unpacked outside the FHS dependency root. Copy it into
    # the rootfs before buildFHSEnv creates its /usr/lib -> /usr/lib64 symlink so
    # the generated /init launcher can find the executable and its adjacent
    # Electron resources at runtime.
    extraBuildCommands = ''
      install -d "$out/usr/lib64"
      cp -a ${contents}/usr/lib/chatgpt "$out/usr/lib64/"
    '';

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
  };

  computerUseVersion =
    (builtins.fromTOML (builtins.readFile "${codex-desktop-linux}/computer-use-linux/Cargo.toml"))
    .package.version;

  computerUseSource =
    runCommandLocal "nixslop-codex-computer-use-source"
      {
        nativeBuildInputs = [ patch ];
      }
      ''
        mkdir -p "$out"
        cp ${codex-desktop-linux}/Cargo.lock "$out/Cargo.lock"
        cat > "$out/Cargo.toml" <<'EOF'
        [workspace]
        members = ["computer-use-linux"]
        resolver = "2"
        EOF
        cp -R ${codex-desktop-linux}/computer-use-linux "$out/computer-use-linux"
        chmod -R u+w "$out"

        patch --batch --fuzz=0 -d "$out" -p1 < ${./computer-use.patch}
        patch --batch --fuzz=0 -d "$out" -p1 < ${./computer-use-grim.patch}
        patch --batch --fuzz=0 -d "$out" -p1 < ${./computer-use-diagnostics-grim.patch}

        registry="$out/computer-use-linux/src/windowing/registry.rs"
        hyprland="$out/computer-use-linux/src/windowing/backends/hyprland.rs"
        screenshot="$out/computer-use-linux/src/screenshot.rs"
        grep -Fq 'HYPRLAND_BACKEND => hyprland::move_window' "$registry"
        grep -Fq 'HYPRLAND_BACKEND => hyprland::resize_window' "$registry"
        grep -Fq 'hl.dsp.window.{dispatcher}' "$hyprland"
        grep -Fq 'capture_with_grim' "$screenshot"
        grep -Fq 'Self::Grim' "$screenshot"
        test "$(sed -n '/const BACKEND_ORDER/,/];/p' "$registry" | grep -n 'BackendKind::' | head -n 1 | cut -d: -f2-)" = \
          '    BackendKind::Hyprland,'
      '';

  computerUseBinaries = rustPlatform.buildRustPackage {
    pname = "nixslop-codex-computer-use-linux-binaries";
    version = computerUseVersion;
    src = computerUseSource;

    cargoLock.lockFile = "${codex-desktop-linux}/Cargo.lock";

    buildAndTestSubdir = "computer-use-linux";
    cargoBuildFlags = [
      "-p"
      "codex-computer-use-linux"
      "--bins"
    ];
    doCheck = false;
    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      runHook preInstall
      release_dir="target/''${CARGO_BUILD_TARGET:-${stdenvNoCC.hostPlatform.rust.rustcTarget}}/release"
      if [ ! -d "$release_dir" ]; then
        release_dir="target/release"
      fi
      install -Dm0755 "$release_dir/codex-computer-use-linux" "$out/bin/codex-computer-use-linux.bin"
      makeWrapper "$out/bin/codex-computer-use-linux.bin" "$out/bin/codex-computer-use-linux" \
        --prefix PATH : ${lib.makeBinPath [ grim ]}
      install -Dm0755 "$release_dir/codex-computer-use-cosmic" "$out/bin/codex-computer-use-cosmic"
      install -Dm0755 "$release_dir/codex-chrome-extension-host" "$out/bin/codex-chrome-extension-host"
      runHook postInstall
    '';

    passthru = {
      inherit computerUseSource;
    };
  };

  upstreamComputerUsePackage =
    (codex-desktop-linux.packages.${system}.codex-desktop-computer-use-ui).overrideAttrs
      (old: {
        postInstall = (old.postInstall or "") + ''
          plugin_dir="$out/opt/codex-desktop/resources/plugins/openai-bundled/plugins/computer-use"
          test -f "$plugin_dir/.codex-plugin/plugin.json"
          install -Dm0644 ${codex-desktop-linux}/assets/codex-linux.png "$plugin_dir/assets/app-icon.png"
          install -Dm0755 ${computerUseBinaries}/bin/codex-computer-use-linux "$plugin_dir/bin/codex-computer-use-linux"
          install -Dm0755 ${computerUseBinaries}/bin/codex-computer-use-cosmic "$plugin_dir/bin/codex-computer-use-cosmic"
          install -Dm0755 ${computerUseBinaries}/bin/codex-chrome-extension-host "$plugin_dir/bin/codex-chrome-extension-host"
        '';
      });

  computerUsePackage = symlinkJoin {
    name = "chatgpt-desktop-${source.version}-computer-use";
    paths = [ upstreamComputerUsePackage ];
    nativeBuildInputs = [ makeWrapper ];

    postBuild = ''
      makeWrapper ${upstreamComputerUsePackage}/bin/codex-desktop "$out/bin/chatgpt"

      if [ -f "$out/share/applications/codex-desktop.desktop" ]; then
        cp -L "$out/share/applications/codex-desktop.desktop" "$out/share/applications/chatgpt.desktop"
        substituteInPlace "$out/share/applications/chatgpt.desktop" \
          --replace-fail "${upstreamComputerUsePackage}/bin/codex-desktop" "$out/bin/chatgpt" \
          --replace-fail "Name=ChatGPT Community" "Name=ChatGPT" \
          --replace-fail " %u" " %U"
      fi
    '';

    passthru = {
      inherit computerUseBinaries upstreamComputerUsePackage;
      inherit enableComputerUseUi linuxFeatureIds linuxFeaturesConfigOverride;
    };

    meta = officialPackage.meta or { };
  };
in
if enableComputerUseUi then computerUsePackage else officialPackage
