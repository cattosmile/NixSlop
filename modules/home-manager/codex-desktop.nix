{
  self,
}:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.codexDesktopLinux;
  remoteCfg = cfg.remoteControl;
  system = pkgs.stdenv.hostPlatform.system;
  basePackage = cfg.package;
  codexCliPath = if cfg.cliPackage == null then null else lib.getExe' cfg.cliPackage "codex";
  remoteEnvironmentFilePath =
    if remoteCfg.environmentFile == null then null else lib.removePrefix "-" remoteCfg.environmentFile;
  remoteEnvironmentFileSegments =
    if remoteEnvironmentFilePath == null then
      [ ]
    else
      lib.drop 1 (lib.splitString "/" remoteEnvironmentFilePath);
  remoteEnvironmentFileIsCanonical =
    remoteEnvironmentFilePath != null
    && lib.hasPrefix "/" remoteEnvironmentFilePath
    && lib.all (
      segment: segment != "" && segment != "." && segment != ".."
    ) remoteEnvironmentFileSegments;

  withCodexCliPath =
    base:
    pkgs.symlinkJoin {
      name = "${base.name}-codex-cli-path";
      paths = [ base ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        if [ -e "$out/bin/chatgpt" ]; then
          rm -f "$out/bin/chatgpt" "$out/bin/codex-desktop"
          makeWrapper "${base}/bin/chatgpt" "$out/bin/chatgpt" \
            --set-default CODEX_CLI_PATH "${codexCliPath}"
          ln -s chatgpt "$out/bin/codex-desktop"
        fi

        desktopFile="$out/share/applications/chatgpt.desktop"
        if [ -e "$desktopFile" ]; then
          target="$(readlink -f "$desktopFile")"
          rm -f "$desktopFile"
        install -Dm0644 "$target" "$desktopFile"
        substituteInPlace "$desktopFile" \
          --replace-fail "${base}/bin/chatgpt" "$out/bin/chatgpt"
        fi
      '';
      meta = base.meta or { };
    };

  desktopPackage =
    if basePackage == null then
      null
    else if codexCliPath == null then
      basePackage
    else
      withCodexCliPath basePackage;

  codexHome =
    if remoteCfg.codexHome != null then remoteCfg.codexHome else "${config.home.homeDirectory}/.codex";
  remoteControlPath = lib.makeSearchPath "bin" (
    [ config.home.profileDirectory ] ++ remoteCfg.extraPackages
  );
  remoteControlEnvironment = {
    CODEX_HOME = codexHome;
    PATH = remoteControlPath;
  }
  // remoteCfg.environment;
  remoteControlEnvironmentList = lib.mapAttrsToList (
    name: value: "${name}=${if lib.isBool value then lib.boolToString value else toString value}"
  ) (lib.filterAttrs (_name: value: value != null) remoteControlEnvironment);
in
{
  imports = [ self.homeManagerModules.codexComputerUseHyprland ];

  options.programs.codexDesktopLinux = {
    enable = lib.mkEnableOption "the official ChatGPT Desktop app for Linux";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default =
        if cfg.computerUseUi.enable then
          self.packages.${system}.codex-desktop-computer-use-ui
        else
          self.packages.${system}.chatgpt-desktop;
      defaultText = lib.literalExpression ''
        if config.programs.codexDesktopLinux.computerUseUi.enable
        then inputs.nixslop.packages.\${pkgs.stdenv.hostPlatform.system}.codex-desktop-computer-use-ui
        else inputs.nixslop.packages.\${pkgs.stdenv.hostPlatform.system}.chatgpt-desktop
      '';
      description = ''
        Official ChatGPT Desktop package to install. Enabling
        `computerUseUi.enable` selects the NixSlop package variant that adds
        the community Linux Computer Use plugin and Hyprland backend to the
        official app. Set this explicitly to override that selection.
        Set this to null to manage the application outside Home Manager.
      '';
    };

    cliPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = self.packages.${system}.codex;
      defaultText = lib.literalExpression "inputs.nixslop.packages.\${pkgs.stdenv.hostPlatform.system}.codex";
      description = ''
        Codex CLI package exposed to the official desktop launcher through
        CODEX_CLI_PATH. Set this to null to let the app discover Codex itself.
      '';
    };

    computerUseUi.enable = lib.mkEnableOption ''
      the Linux Computer Use UI and Hyprland plugin integration. This selects
      the official ChatGPT Desktop package with NixSlop's Linux Computer Use
      plugin and feature patches.
    '';

    remoteMobileControl.enable = lib.mkEnableOption ''
      the Remote Mobile Control compatibility flag. Availability is managed by
      the official application rather than a NixSlop package patch.
    '';

    linuxFeatures = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Historical Linux feature IDs retained for compatibility. The official
        package is not rebuilt or patched based on this list.
      '';
    };

    remoteControl = {
      enable = lib.mkEnableOption "a user systemd app-server with remote control enabled";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.codex;
        defaultText = lib.literalExpression "pkgs.codex";
        description = "Codex CLI package used by the remote-control app-server service.";
      };

      codexHome = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "\${config.home.homeDirectory}/.codex";
        description = "Value for CODEX_HOME in the remote-control service.";
      };

      listen = lib.mkOption {
        type = lib.types.str;
        default = "unix://";
        description = "Local app-server transport endpoint passed to codex app-server --listen.";
      };

      target = lib.mkOption {
        type = lib.types.str;
        default = "default.target";
        description = "Systemd user target that starts the remote-control service.";
      };

      environment = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.nullOr (
            lib.types.oneOf [
              lib.types.bool
              lib.types.int
              lib.types.str
            ]
          )
        );
        default = { };
        description = "Environment variables for the remote-control service.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/run/secrets/codex-remote-control.env";
        description = "Runtime path to an additional systemd environment file.";
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs; [
          bash
          coreutils
          findutils
          git
          gnugrep
          gnused
          openssh
        ];
        description = "Extra packages to add to PATH for commands launched by Codex.";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional arguments passed to codex app-server.";
      };

      disableLauncherAutostart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Disable the mutable standalone remote-control daemon hook.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !remoteCfg.enable || pkgs.stdenv.hostPlatform.isLinux;
        message = "programs.codexDesktopLinux.remoteControl.enable is only supported on Linux";
      }
      {
        assertion =
          remoteCfg.environmentFile == null
          || (!builtins.hasContext remoteCfg.environmentFile && remoteEnvironmentFileIsCanonical);
        message = "programs.codexDesktopLinux.remoteControl.environmentFile must be an absolute canonical runtime path outside the Nix store";
      }
    ];

    home.packages = lib.optional (desktopPackage != null) desktopPackage;

    home.sessionVariables = lib.mkIf (remoteCfg.enable && remoteCfg.disableLauncherAutostart) {
      CODEX_REMOTE_CONTROL_DAEMON_AUTOSTART_DISABLED = "1";
    };

    systemd.user.sessionVariables = lib.mkIf (remoteCfg.enable && remoteCfg.disableLauncherAutostart) {
      CODEX_REMOTE_CONTROL_DAEMON_AUTOSTART_DISABLED = "1";
    };

    systemd.user.services.codex-remote-control = lib.mkIf remoteCfg.enable {
      Unit = {
        Description = "Codex remote-control app-server";
        After = [ "network.target" ];
      };

      Service = {
        Environment = remoteControlEnvironmentList;
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe remoteCfg.package)
            "app-server"
            "--remote-control"
            "--listen"
            remoteCfg.listen
          ]
          ++ remoteCfg.extraArgs
        );
        Restart = "on-failure";
        RestartSec = 5;
      }
      // lib.optionalAttrs (remoteCfg.environmentFile != null) {
        EnvironmentFile = remoteCfg.environmentFile;
      };

      Install.WantedBy = [ remoteCfg.target ];
    };
  };
}
