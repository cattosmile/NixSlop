{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  rustPlatform,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs,
  pkg-config,
  wrapGAppsHook3,
  desktop-file-utils,
  glib-networking,
  libayatana-appindicator,
  openssl,
  webkitgtk_4_1,
  bubblewrap,
  bash,
  coreutils,
  defaultLanguage ? "en",
  defaultCodexConfigDir ? null,
  sandboxCodexDir ? null,
  sandboxAgentsDir ? null,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version;
  defaultSettingsJson = builtins.toJSON {
    language = defaultLanguage;
    codexConfigDir = defaultCodexConfigDir;
    launchOnStartup = false;
    useAppWindowControls = true;
    visibleApps = {
      claude = false;
      "claude-desktop" = false;
      codex = true;
      gemini = false;
      grokbuild = false;
      opencode = false;
      openclaw = false;
      hermes = false;
    };
    showProfileSwitcher = false;
    preferredTerminal = "alacritty";
  };

  nativeApp = rustPlatform.buildRustPackage (finalAttrs: {
    pname = "cc-switch-native";
    inherit version;

    src = fetchFromGitHub {
      owner = "farion1231";
      repo = "cc-switch";
      tag = "v${finalAttrs.version}";
      hash = versionData.sourceHash;
    };

    cargoRoot = "src-tauri";
    cargoHash = versionData.cargoHash;

    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs) pname version src;
      pnpm = pnpm_10;
      fetcherVersion = 3;
      hash = versionData.pnpmHash;
    };

    nativeBuildInputs = [
      nodejs
      pkg-config
      pnpmConfigHook
      pnpm_10
      wrapGAppsHook3
    ];

    buildInputs = [
      glib-networking
      libayatana-appindicator
      openssl
      webkitgtk_4_1
    ];

    buildPhase = ''
      runHook preBuild

      export HOME="$TMPDIR"
      export CARGO_PROFILE_RELEASE_STRIP=false
      export CARGO_PROFILE_RELEASE_LTO=false
      export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16

      tauriConf='${builtins.toJSON { bundle.createUpdaterArtifacts = false; }}'
      printf "%s" "$tauriConf" > tauri-conf.nix.json
      pnpm tauri build \
        --no-bundle \
        --config tauri-conf.nix.json \
        -- \
        --offline \
        -j "$NIX_BUILD_CORES"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 src-tauri/target/release/cc-switch "$out/bin/cc-switch"
      install -Dm444 \
        src-tauri/icons/128x128.png \
        "$out/share/icons/hicolor/128x128/apps/cc-switch.png"
      install -Dm444 \
        src-tauri/icons/32x32.png \
        "$out/share/icons/hicolor/32x32/apps/cc-switch.png"
      install -Dm444 /dev/stdin "$out/share/applications/cc-switch.desktop" <<'EOF'
      [Desktop Entry]
      Type=Application
      Name=CC Switch
      Comment=All-in-One Assistant for Claude Code, Codex and Gemini CLI
      Exec=cc-switch
      Icon=cc-switch
      Terminal=false
      Categories=Development;
      EOF

      runHook postInstall
    '';

    preFixup = ''
      gappsWrapperArgs+=(
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libayatana-appindicator ]}
        --prefix PATH : ${lib.makeBinPath [ desktop-file-utils ]}
      )
    '';

    doCheck = false;

    meta.sourceProvenance = [ lib.sourceTypes.fromSource ];
  });
in
stdenvNoCC.mkDerivation {
  pname = "cc-switch";
  inherit version;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec" "$out/share"
    ln -s ${nativeApp}/bin/cc-switch "$out/libexec/cc-switch-native"
    ln -s ${nativeApp}/share/applications "$out/share/applications"
    ln -s ${nativeApp}/share/icons "$out/share/icons"

    install -Dm555 /dev/stdin "$out/libexec/cc-switch-initialize-settings" <<'EOF'
    #!${bash}/bin/bash
    set -euo pipefail

    if [[ ''${HOME:-} != /* || ''${HOME:-} == / ]]; then
      echo "cc-switch: HOME must be an absolute non-root path" >&2
      exit 2
    fi

    settings_dir="$HOME/.cc-switch"
    settings_file="$settings_dir/settings.json"
    ${coreutils}/bin/mkdir -p -- "$settings_dir"
    ${coreutils}/bin/chmod 700 -- "$settings_dir"

    # The file belongs to the user and is intentionally mutable.  Only create
    # it when it is absent; the hard-link commit keeps concurrent launches from
    # replacing a file created by another process in the meantime.
    if [[ -e "$settings_file" ]]; then
      exit 0
    fi

    umask 077
    temporary_file="$(${coreutils}/bin/mktemp "$settings_dir/.settings.json.XXXXXX")"
    cleanup() {
      ${coreutils}/bin/rm -f -- "$temporary_file"
    }
    trap cleanup EXIT

    ${coreutils}/bin/printf '%s\n' ${lib.escapeShellArg defaultSettingsJson} > "$temporary_file"
    ${coreutils}/bin/chmod 600 -- "$temporary_file"
    if ${coreutils}/bin/ln -- "$temporary_file" "$settings_file" 2>/dev/null; then
      :
    fi
    exit 0
    EOF

    install -Dm555 /dev/stdin "$out/libexec/cc-switch-sandbox-probe-init" <<'EOF'
    #!${bash}/bin/bash
    set -euo pipefail

    [[ $PWD == "$HOME" ]]
    [[ $(<"$HOME/.codex/sentinel") == "isolated-codex" ]]
    [[ $(<"$HOME/.agents/sentinel") == "isolated-agents" ]]
    [[ $(<"$XDG_CONFIG_HOME/autostart/sentinel") == "isolated-autostart" ]]
    [[ $(<"$HOME/.config/autostart/sentinel") == "isolated-autostart" ]]
    [[ $(<"$XDG_CONFIG_HOME/mimeapps.list") == "isolated-mimeapps" ]]
    [[ $(<"$XDG_DATA_HOME/applications/sentinel") == "isolated-applications" ]]
    [[ ! -e "$HOME/.codex/host-only" ]]
    [[ ! -e "$HOME/.agents/host-only" ]]
    [[ ! -e "$XDG_CONFIG_HOME/autostart/host-only" ]]
    [[ ! -e "$HOME/.config/autostart/host-only" ]]
    [[ ! -e "$XDG_DATA_HOME/applications/host-only" ]]
    printf "%s\n" sandbox-codex > "$HOME/.codex/sandbox-write"
    printf "%s\n" sandbox-agents > "$HOME/.agents/sandbox-write"
    printf "%s\n" sandbox-autostart > "$XDG_CONFIG_HOME/autostart/sandbox-write"
    printf "%s\n" sandbox-legacy-autostart > "$HOME/.config/autostart/legacy-sandbox-write"
    printf "%s\n" sandbox-mimeapps > "$XDG_CONFIG_HOME/mimeapps.list"
    printf "%s\n" sandbox-applications > "$XDG_DATA_HOME/applications/sandbox-write"
    EOF

    install -Dm555 /dev/stdin "$out/libexec/cc-switch-sandbox" <<'EOF'
    #!${bash}/bin/bash
    set -euo pipefail

    if [[ ''${HOME:-} != /* || ''${HOME:-} == / ]]; then
      echo "cc-switch: HOME must be an absolute non-root path" >&2
      exit 2
    fi
    package_root="$(${coreutils}/bin/realpath -- "$(${coreutils}/bin/dirname -- "$0")/..")"

    mode="''${1:-}"
    if [[ $mode == --app ]]; then
      shift
      "$package_root/libexec/cc-switch-initialize-settings"
      command=(${lib.escapeShellArg "${nativeApp}/bin/cc-switch"} "$@")
      probe_mode=false
    elif [[ $mode == --probe ]]; then
      if [[ $# != 2 || $2 != /* || $2 == / ]]; then
        echo "cc-switch: invalid fixed probe invocation" >&2
        exit 2
      fi
      probe_mode=true
      probe_root="$(${coreutils}/bin/realpath -- "$2")"
      if [[ $probe_root != "$2" \
        || $(${coreutils}/bin/stat -c %u -- "$probe_root") != $(${coreutils}/bin/id -u) \
        || $(${coreutils}/bin/stat -c %a -- "$probe_root") != 700 \
        || $HOME != "$probe_root/home" \
        || ''${XDG_STATE_HOME:-} != "$probe_root/state" \
        || ''${XDG_CONFIG_HOME:-} != "$probe_root/config" \
        || ''${XDG_DATA_HOME:-} != "$probe_root/data" ]]; then
        echo "cc-switch: unsafe fixed probe root" >&2
        exit 2
      fi
      if [[ $(<"$probe_root/state/cc-switch/codex/sentinel") != isolated-codex \
        || $(<"$probe_root/state/cc-switch/agents/sentinel") != isolated-agents \
        || $(<"$probe_root/state/cc-switch/config/autostart/sentinel") != isolated-autostart \
        || $(<"$probe_root/state/cc-switch/config/mimeapps.list") != isolated-mimeapps \
        || $(<"$probe_root/state/cc-switch/applications/sentinel") != isolated-applications \
        || $(<"$probe_root/home/.codex/host-only") != host-codex \
        || $(<"$probe_root/home/.agents/host-only") != host-agents \
        || $(<"$probe_root/home/.config/autostart/host-only") != host-legacy-autostart \
        || $(<"$probe_root/config/autostart/host-only") != host-autostart \
        || $(<"$probe_root/config/mimeapps.list") != host-mimeapps \
        || $(<"$probe_root/data/applications/host-only") != host-applications ]]; then
        echo "cc-switch: invalid fixed probe sentinels" >&2
        exit 2
      fi
      command=("$package_root/libexec/cc-switch-sandbox-probe-init")
    else
      echo "cc-switch: invalid sandbox mode" >&2
      exit 2
    fi

    state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
    config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
    data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
    legacy_config_home="$HOME/.config"
    if [[ $state_home != /* || $config_home != /* || $data_home != /* ]]; then
      echo "cc-switch: XDG state, config, and data homes must be absolute paths" >&2
      exit 2
    fi

    state_root="$state_home/cc-switch"
    if $probe_mode; then
      codex_state="$state_root/codex"
      agents_state="$state_root/agents"
    else
      codex_state=${
        if sandboxCodexDir == null then
          ''"$state_root/codex"''
        else
          lib.escapeShellArg (toString sandboxCodexDir)
      }
      agents_state=${
        if sandboxAgentsDir == null then
          ''"$state_root/agents"''
        else
          lib.escapeShellArg (toString sandboxAgentsDir)
      }
    fi
    config_state="$state_root/config"
    applications_state="$state_root/applications"
    if [[ $codex_state != /* || $agents_state != /* \
      || $config_state != /* || $applications_state != /* ]]; then
      echo "cc-switch: sandbox state directories must be absolute paths" >&2
      exit 2
    fi

    state_paths=(
      "$codex_state"
      "$agents_state"
      "$config_state"
      "$applications_state"
    )
    for state_path in "''${state_paths[@]}"; do
      if [[ -L $state_path ]]; then
        echo "cc-switch: sandbox state directories must not be symbolic links" >&2
        exit 2
      fi
    done

    codex_state_real="$(${coreutils}/bin/realpath -m -- "$codex_state")"
    agents_state_real="$(${coreutils}/bin/realpath -m -- "$agents_state")"
    config_state_real="$(${coreutils}/bin/realpath -m -- "$config_state")"
    applications_state_real="$(${coreutils}/bin/realpath -m -- "$applications_state")"
    protected_codex="$(${coreutils}/bin/realpath -m -- "$HOME/.codex")"
    protected_agents="$(${coreutils}/bin/realpath -m -- "$HOME/.agents")"
    protected_config="$(${coreutils}/bin/realpath -m -- "$config_home")"
    protected_legacy_config="$(${coreutils}/bin/realpath -m -- "$legacy_config_home")"
    protected_applications="$(${coreutils}/bin/realpath -m -- "$data_home/applications")"

    paths_overlap() {
      [[ $1 == "$2" || $1 == "$2/"* || $2 == "$1/"* ]]
    }

    state_dirs=(
      "$codex_state_real"
      "$agents_state_real"
      "$config_state_real"
      "$applications_state_real"
    )
    protected_dirs=(
      "$protected_codex"
      "$protected_agents"
      "$protected_config"
      "$protected_applications"
    )
    if [[ $protected_legacy_config != "$protected_config" ]]; then
      protected_dirs+=("$protected_legacy_config")
    fi
    for state_dir in "''${state_dirs[@]}"; do
      for protected_dir in "''${protected_dirs[@]}"; do
        if paths_overlap "$state_dir" "$protected_dir"; then
          echo "cc-switch: sandbox state directories overlap protected directories" >&2
          exit 2
        fi
      done
    done
    for ((i = 0; i < ''${#state_dirs[@]}; i++)); do
      for ((j = i + 1; j < ''${#state_dirs[@]}; j++)); do
        if paths_overlap "''${state_dirs[i]}" "''${state_dirs[j]}"; then
          echo "cc-switch: sandbox state directories overlap peer directories" >&2
          exit 2
        fi
      done
    done
    for ((i = 0; i < ''${#protected_dirs[@]}; i++)); do
      for ((j = i + 1; j < ''${#protected_dirs[@]}; j++)); do
        if paths_overlap "''${protected_dirs[i]}" "''${protected_dirs[j]}"; then
          echo "cc-switch: protected directories overlap each other" >&2
          exit 2
        fi
      done
    done

    umask 077
    ${coreutils}/bin/mkdir -p -- \
      "$state_root" "$codex_state" "$agents_state" \
      "$config_state" "$applications_state" \
      "$HOME/.codex" "$HOME/.agents" \
      "$config_home" "$legacy_config_home" "$data_home/applications"

    for ((i = 0; i < ''${#state_paths[@]}; i++)); do
      if [[ $(${coreutils}/bin/realpath -- "''${state_paths[i]}") != "''${state_dirs[i]}" ]]; then
        echo "cc-switch: sandbox state path changed during validation" >&2
        exit 2
      fi
    done

    private_dirs=("$state_root" "''${state_paths[@]}")
    current_uid="$(${coreutils}/bin/id -u)"
    for private_dir in "''${private_dirs[@]}"; do
      if [[ ! -d $private_dir || -L $private_dir \
        || $(${coreutils}/bin/stat -c %u -- "$private_dir") != "$current_uid" ]]; then
        echo "cc-switch: sandbox state directories must be real directories owned by the current user" >&2
        exit 2
      fi
      private_mode="$(${coreutils}/bin/stat -c %a -- "$private_dir")"
      if (( (8#$private_mode & 077) != 0 )); then
        echo "cc-switch: sandbox state directories must not grant group or world access" >&2
        exit 2
      fi
    done

    config_binds=(--bind "$config_state_real" "$protected_config")
    if [[ $protected_legacy_config != "$protected_config" ]]; then
      config_binds+=(--bind "$config_state_real" "$protected_legacy_config")
    fi

    exec ${bubblewrap}/bin/bwrap \
      --die-with-parent \
      --new-session \
      --bind / / \
      --dev-bind /dev /dev \
      --proc /proc \
      --bind "$codex_state_real" "$protected_codex" \
      --bind "$agents_state_real" "$protected_agents" \
      "''${config_binds[@]}" \
      --bind "$applications_state_real" "$protected_applications" \
      --setenv HOME "$HOME" \
      --setenv XDG_STATE_HOME "$state_home" \
      --setenv XDG_CONFIG_HOME "$config_home" \
      --setenv XDG_DATA_HOME "$data_home" \
      --chdir "$HOME" \
      -- \
      "''${command[@]}"
    EOF

    install -Dm555 /dev/stdin "$out/bin/cc-switch" <<EOF
    #!${bash}/bin/bash
    exec "$out/libexec/cc-switch-sandbox" --app "\$@"
    EOF

    install -Dm555 /dev/stdin "$out/bin/cc-switch-sandbox-probe" <<EOF
    #!${bash}/bin/bash
    set -euo pipefail

    probe_root="\$(${coreutils}/bin/mktemp -d)"
    ${coreutils}/bin/chmod 0700 "\$probe_root"
    cleanup() {
      ${coreutils}/bin/rm -rf -- "\$probe_root"
    }
    trap cleanup EXIT

    probe_home="\$probe_root/home"
    probe_state="\$probe_root/state"
    probe_config="\$probe_root/config"
    probe_data="\$probe_root/data"
    umask 077
    ${coreutils}/bin/mkdir -p \
      "\$probe_home/.codex" \
      "\$probe_home/.agents" \
      "\$probe_home/.config/autostart" \
      "\$probe_config/autostart" \
      "\$probe_data/applications" \
      "\$probe_state/cc-switch/codex" \
      "\$probe_state/cc-switch/agents" \
      "\$probe_state/cc-switch/config/autostart" \
      "\$probe_state/cc-switch/applications"

    ${coreutils}/bin/printf '%s\n' host-codex > "\$probe_home/.codex/host-only"
    ${coreutils}/bin/printf '%s\n' host-agents > "\$probe_home/.agents/host-only"
    ${coreutils}/bin/printf '%s\n' host-legacy-autostart > "\$probe_home/.config/autostart/host-only"
    ${coreutils}/bin/printf '%s\n' host-autostart > "\$probe_config/autostart/host-only"
    ${coreutils}/bin/printf '%s\n' host-mimeapps > "\$probe_config/mimeapps.list"
    ${coreutils}/bin/printf '%s\n' host-applications > "\$probe_data/applications/host-only"
    ${coreutils}/bin/printf '%s\n' isolated-codex > "\$probe_state/cc-switch/codex/sentinel"
    ${coreutils}/bin/printf '%s\n' isolated-agents > "\$probe_state/cc-switch/agents/sentinel"
    ${coreutils}/bin/printf '%s\n' isolated-autostart > "\$probe_state/cc-switch/config/autostart/sentinel"
    ${coreutils}/bin/printf '%s\n' isolated-mimeapps > "\$probe_state/cc-switch/config/mimeapps.list"
    ${coreutils}/bin/printf '%s\n' isolated-applications > "\$probe_state/cc-switch/applications/sentinel"

    ${coreutils}/bin/chmod 0755 "\$probe_state/cc-switch/codex"
    if HOME="\$probe_home" \
      XDG_STATE_HOME="\$probe_state" \
      XDG_CONFIG_HOME="\$probe_config" \
      XDG_DATA_HOME="\$probe_data" \
      "$out/libexec/cc-switch-sandbox" --probe "\$probe_root" 2>/dev/null; then
      echo "cc-switch sandbox probe: insecure state permissions were accepted" >&2
      exit 1
    fi
    [[ \$(${coreutils}/bin/stat -c %a -- "\$probe_state/cc-switch/codex") == 755 ]]
    [[ ! -e "\$probe_state/cc-switch/codex/sandbox-write" ]]
    ${coreutils}/bin/chmod 0700 "\$probe_state/cc-switch/codex"

    (
      cd "\$probe_home/.codex"
      HOME="\$probe_home" \
        XDG_STATE_HOME="\$probe_state" \
        XDG_CONFIG_HOME="\$probe_config" \
        XDG_DATA_HOME="\$probe_data" \
        "$out/libexec/cc-switch-sandbox" \
        --probe "\$probe_root"
    )

    [[ \$(<"\$probe_home/.codex/host-only") == host-codex ]]
    [[ \$(<"\$probe_home/.agents/host-only") == host-agents ]]
    [[ \$(<"\$probe_home/.config/autostart/host-only") == host-legacy-autostart ]]
    [[ \$(<"\$probe_config/autostart/host-only") == host-autostart ]]
    [[ \$(<"\$probe_config/mimeapps.list") == host-mimeapps ]]
    [[ \$(<"\$probe_data/applications/host-only") == host-applications ]]
    [[ ! -e "\$probe_home/.codex/sandbox-write" ]]
    [[ ! -e "\$probe_home/.agents/sandbox-write" ]]
    [[ ! -e "\$probe_home/.config/autostart/legacy-sandbox-write" ]]
    [[ ! -e "\$probe_config/autostart/sandbox-write" ]]
    [[ ! -e "\$probe_data/applications/sandbox-write" ]]
    [[ \$(<"\$probe_state/cc-switch/codex/sandbox-write") == sandbox-codex ]]
    [[ \$(<"\$probe_state/cc-switch/agents/sandbox-write") == sandbox-agents ]]
    [[ \$(<"\$probe_state/cc-switch/config/autostart/sandbox-write") == sandbox-autostart ]]
    [[ \$(<"\$probe_state/cc-switch/config/autostart/legacy-sandbox-write") == sandbox-legacy-autostart ]]
    [[ \$(<"\$probe_state/cc-switch/config/mimeapps.list") == sandbox-mimeapps ]]
    [[ \$(<"\$probe_state/cc-switch/applications/sandbox-write") == sandbox-applications ]]
    [[ \$(${coreutils}/bin/stat -c %a -- "\$probe_state/cc-switch/config") == 700 ]]
    [[ \$(${coreutils}/bin/stat -c %a -- "\$probe_state/cc-switch/applications") == 700 ]]

    echo "cc-switch sandbox probe: PASS"
    EOF

    runHook postInstall
  '';

  passthru = {
    inherit nativeApp;
    category = "Developer Tools";
  };

  meta = {
    description = "Cross-platform GUI manager for Claude Code, Codex, and Gemini CLI";
    homepage = "https://github.com/farion1231/cc-switch";
    changelog = "https://github.com/farion1231/cc-switch/releases/tag/v${version}";
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    license = lib.licenses.mit;
    mainProgram = "cc-switch";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
