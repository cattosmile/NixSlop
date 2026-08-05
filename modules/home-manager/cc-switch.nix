{ self }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.ccSwitch;
  system = pkgs.stdenv.hostPlatform.system;
  sharedCodexConfigDir = "${config.home.homeDirectory}/.codex";
  sharedAgentsConfigDir = "${config.home.homeDirectory}/.agents";
  legacyCodexConfigDir = "${config.xdg.stateHome}/cc-switch/codex";
  normalizePath =
    path:
    if path == "/" then
      path
    else if lib.hasSuffix "/" path then
      normalizePath (lib.removeSuffix "/" path)
    else
      path;
  isAtOrBelow =
    parent: child:
    let
      normalizedParent = normalizePath parent;
      normalizedChild = normalizePath child;
    in
    normalizedChild == normalizedParent
    || (normalizedParent == "/" && lib.hasPrefix "/" normalizedChild)
    || lib.hasPrefix "${normalizedParent}/" normalizedChild;
  pathsOverlap = left: right: isAtOrBelow left right || isAtOrBelow right left;
  usesSharedConfig =
    directory:
    lib.any (pathsOverlap directory) [
      sharedCodexConfigDir
      sharedAgentsConfigDir
    ];
  isSafeAbsolutePath =
    path:
    lib.hasPrefix "/" path
    && !lib.any (component: component == "." || component == "..") (lib.splitString "/" path);
in
{
  options.programs.ccSwitch = {
    enable = lib.mkEnableOption "CC Switch desktop application";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.cc-switch.override {
        defaultLanguage = cfg.language;
        defaultCodexConfigDir = cfg.codexConfigDir;
        sandboxCodexDir = cfg.codexConfigDir;
        sandboxAgentsDir = cfg.agentsConfigDir;
        allowSharedCodexDir = cfg.codexConfigDir == sharedCodexConfigDir;
      };
      defaultText = lib.literalExpression ''
        inputs.nixslop.packages.${pkgs.stdenv.hostPlatform.system}.cc-switch.override {
          defaultLanguage = config.programs.ccSwitch.language;
          defaultCodexConfigDir = config.programs.ccSwitch.codexConfigDir;
          sandboxCodexDir = config.programs.ccSwitch.codexConfigDir;
          sandboxAgentsDir = config.programs.ccSwitch.agentsConfigDir;
          allowSharedCodexDir =
            config.programs.ccSwitch.codexConfigDir == "${config.home.homeDirectory}/.codex";
        }
      '';
      description = "Sandboxed CC Switch package to install.";
    };

    language = lib.mkOption {
      type = lib.types.enum [
        "en"
        "ja"
        "zh"
        "zh-TW"
      ];
      default = "en";
      description = "Language used by CC Switch.";
    };

    codexConfigDir = lib.mkOption {
      type = lib.types.str;
      default = sharedCodexConfigDir;
      defaultText = lib.literalExpression ''"${config.home.homeDirectory}/.codex"'';
      description = ''
        Codex configuration directory managed by CC Switch. The default is
        the user's normal ~/.codex directory so native Codex logins and
        provider switching use the same auth.json. The package sandbox keeps
        Codex plugin/OMX state separate even when this directory is shared.
        Set this to an isolated path if a fully separate Codex instance is
        required.
      '';
    };

    agentsConfigDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/cc-switch/agents";
      defaultText = lib.literalExpression ''"${config.xdg.stateHome}/cc-switch/agents"'';
      description = ''
        Isolated Agents configuration directory exposed inside the CC Switch
        package sandbox instead of the user's real ~/.agents directory.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          isSafeAbsolutePath cfg.codexConfigDir
          && (cfg.codexConfigDir == sharedCodexConfigDir || !usesSharedConfig cfg.codexConfigDir);
        message = ''
          programs.ccSwitch.codexConfigDir must be an absolute path outside
          the shared ${sharedAgentsConfigDir} directory. The default
          ${sharedCodexConfigDir} is intentionally shared so native Codex
          OAuth logins are visible to CC Switch.
        '';
      }
      {
        assertion = isSafeAbsolutePath cfg.agentsConfigDir && !usesSharedConfig cfg.agentsConfigDir;
        message = ''
          programs.ccSwitch.agentsConfigDir must be an absolute path outside
          the shared ${sharedCodexConfigDir} and ${sharedAgentsConfigDir}
          directories. CC Switch is intentionally isolated from the user's
          real configuration.
        '';
      }
      {
        assertion = !pathsOverlap cfg.codexConfigDir cfg.agentsConfigDir;
        message = ''
          programs.ccSwitch.codexConfigDir and agentsConfigDir must be
          separate, non-overlapping directories so the package sandbox can
          mount them independently.
        '';
      }
    ];

    home.packages = [ cfg.package ];

    # Migrate the old NixSlop default once. User-edited settings remain
    # untouched; only the exact former isolated path is moved to ~/.codex.
    home.activation.migrateCcSwitchCodexConfigDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings_file="${config.home.homeDirectory}/.cc-switch/settings.json"
      legacy_codex_dir=${lib.escapeShellArg legacyCodexConfigDir}
      shared_codex_dir=${lib.escapeShellArg sharedCodexConfigDir}

      if [ -f "$settings_file" ] && ${pkgs.jq}/bin/jq -e --arg legacy "$legacy_codex_dir" \
        '.codexConfigDir == $legacy' "$settings_file" >/dev/null; then
        umask 077
        temporary_file="$(${pkgs.coreutils}/bin/mktemp "${config.home.homeDirectory}/.cc-switch/.settings.json.XXXXXX")"
        trap '${pkgs.coreutils}/bin/rm -f "$temporary_file"' EXIT
        ${pkgs.jq}/bin/jq --arg shared "$shared_codex_dir" \
          '.codexConfigDir = $shared' "$settings_file" > "$temporary_file"
        ${pkgs.coreutils}/bin/chmod 600 "$temporary_file"
        ${pkgs.coreutils}/bin/mv "$temporary_file" "$settings_file"
        trap - EXIT
      fi
    '';

    # settings.json is intentionally mutable upstream. Seed first-install
    # defaults atomically, but never rewrite an existing user's settings.
    home.activation.initializeCcSwitchSettings =
      lib.hm.dag.entryAfter [ "migrateCcSwitchCodexConfigDir" ]
        ''
          settings_dir="${config.home.homeDirectory}/.cc-switch"
          settings_file="$settings_dir/settings.json"

          ${pkgs.coreutils}/bin/mkdir -p "$settings_dir"
          ${pkgs.coreutils}/bin/chmod 700 "$settings_dir"

          if [ -e "$settings_file" ]; then
            if ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$settings_file" >/dev/null; then
              echo "CC Switch settings must contain a JSON object: $settings_file" >&2
              exit 1
            fi
          else
            umask 077
            temporary_file="$(${pkgs.coreutils}/bin/mktemp "$settings_dir/.settings.json.XXXXXX")"
            trap '${pkgs.coreutils}/bin/rm -f "$temporary_file"' EXIT

            ${pkgs.jq}/bin/jq -n \
              --arg language ${lib.escapeShellArg cfg.language} \
              --arg codexConfigDir ${lib.escapeShellArg cfg.codexConfigDir} \
              ' {
                language: $language,
                codexConfigDir: $codexConfigDir,
                launchOnStartup: false,
                useAppWindowControls: true,
                visibleApps: {
                  claude: false,
                  "claude-desktop": false,
                  codex: true,
                  gemini: false,
                  grokbuild: false,
                  opencode: false,
                  openclaw: false,
                  hermes: false
                },
                showProfileSwitcher: false,
                preferredTerminal: "alacritty"
              }' \
              > "$temporary_file"

            ${pkgs.coreutils}/bin/chmod 600 "$temporary_file"
            ${pkgs.coreutils}/bin/mv "$temporary_file" "$settings_file"
            trap - EXIT
          fi
        '';
  };
}
