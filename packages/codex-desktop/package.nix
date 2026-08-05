{
  jq,
  lib,
  makeWrapper,
  patch,
  runCommandLocal,
  rustPlatform,
  stdenv,
  grim,
  codexDesktopLinux,
  enableComputerUseUi ? false,
  linuxFeatureIds ? [ ],
  linuxFeaturesConfigOverride ? null,
}:

let
  system = stdenv.hostPlatform.system;
  upstreamCodexDesktop = codexDesktopLinux.packages.${system}.codex-desktop;
  # The backend crate and the bundled Codex plugin have independent release
  # versions; this derivation represents the three Rust binaries.
  computerUseVersion =
    (builtins.fromTOML (builtins.readFile "${codexDesktopLinux}/computer-use-linux/Cargo.toml"))
    .package.version;
  effectiveLinuxFeatureIds =
    if linuxFeaturesConfigOverride == null then
      linuxFeatureIds
    else
      linuxFeaturesConfigOverride.enabled or [ ];
  remoteMobileControlRequested = lib.elem "remote-mobile-control" effectiveLinuxFeatureIds;

  computerUseSource =
    runCommandLocal "nixslop-codex-desktop-patch-source"
      {
        nativeBuildInputs = [ patch ];
      }
      ''
        mkdir -p "$out"
        cp ${codexDesktopLinux}/Cargo.lock "$out/Cargo.lock"
        cat > "$out/Cargo.toml" <<'EOF'
        [workspace]
        members = ["computer-use-linux"]
        resolver = "2"
        EOF
        cp -R ${codexDesktopLinux}/computer-use-linux "$out/computer-use-linux"
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

    cargoLock.lockFile = "${codexDesktopLinux}/Cargo.lock";

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
      release_dir="target/''${CARGO_BUILD_TARGET:-${stdenv.hostPlatform.rust.rustcTarget}}/release"
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
  };
in
(upstreamCodexDesktop.override {
  inherit enableComputerUseUi linuxFeatureIds linuxFeaturesConfigOverride;
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ jq ];

    postInstall =
      (old.postInstall or "")
      + ''
        plugin_dir="$out/opt/codex-desktop/resources/plugins/openai-bundled/plugins/computer-use"
        test -f "$plugin_dir/assets/app-icon.png"
        install -Dm0644 ${./computer-use-plugin.json} "$plugin_dir/.codex-plugin/plugin.json"
        install -Dm0755 ${computerUseBinaries}/bin/codex-computer-use-linux "$plugin_dir/bin/codex-computer-use-linux"
        install -Dm0755 ${computerUseBinaries}/bin/codex-computer-use-cosmic "$plugin_dir/bin/codex-computer-use-cosmic"
        install -Dm0755 ${computerUseBinaries}/bin/codex-chrome-extension-host "$plugin_dir/bin/codex-chrome-extension-host"

        patch_report="$out/opt/codex-desktop/.codex-linux/patch-report.json"
        test -f "$patch_report"
      ''
      + lib.optionalString enableComputerUseUi ''
        for required_patch in \
          linux-computer-use-ui-feature \
          linux-computer-use-native-desktop-apps \
          linux-computer-use-host-platform \
          linux-computer-use-install-flow; do
          jq -e --arg name "$required_patch" \
            '.patches | any(.name == $name and (.status == "applied" or .status == "already-applied"))' \
            "$patch_report" >/dev/null
        done

        # This upstream patch is deliberately allowed to skip when the current
        # renderer no longer exposes its complete settings-card contract. The
        # four required UI/host/install patches above must still be effective.
        jq -e '
          .patches
          | any(
              .name == "linux-computer-use-ui-availability"
              and (
                .status == "applied"
                or .status == "already-applied"
                or .status == "skipped-optional"
              )
            )
        ' "$patch_report" >/dev/null
      ''
      # NixSlop's named feature output is fail-closed: an explicitly selected
      # Remote feature may not degrade into a nominal-only build.
      + ''
        # The structured override takes precedence over linuxFeatureIds
        # upstream, so validate the effective report rather than raw arguments.
        if ${builtins.toJSON remoteMobileControlRequested}; then
          jq -e '.enabledFeatures | index("remote-mobile-control") != null' \
            "$patch_report" >/dev/null
          jq -e '
            ([.patches[] | select(.featureId == "remote-mobile-control")] | length > 0)
            and
            ([.patches[] | select(.featureId == "remote-mobile-control")]
              | all(.status == "applied" or .status == "already-applied"))
          ' "$patch_report" >/dev/null
        else
          jq -e '.enabledFeatures | index("remote-mobile-control") == null' \
            "$patch_report" >/dev/null
        fi
      '';

    passthru = (old.passthru or { }) // {
      inherit computerUseBinaries computerUseSource;
    };
  })
