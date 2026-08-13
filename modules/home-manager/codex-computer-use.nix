{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:

let
  cfg = config.programs.codexComputerUse;
  legacySystemDaemon =
    osConfig != null && lib.attrByPath [ "services" "codexComputerUse" "enable" ] false osConfig;
  defaultSocket = "${config.xdg.stateHome}/codex-computer-use/ydotool.sock";

  escapeSystemdExecArg =
    arg: lib.replaceStrings [ "%" "$" ] [ "%%" "$$" ] (builtins.toJSON (toString arg));
  escapeSystemdExecArgs = lib.concatMapStringsSep " " escapeSystemdExecArg;
in
{
  options.programs.codexComputerUse = {
    enable = lib.mkEnableOption "the Linux Computer Use runtime";

    atSpiPackage = lib.mkPackageOption pkgs "at-spi2-core" { };

    ydotoolPackage = lib.mkPackageOption pkgs "ydotool" { };

    ydotoold = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = !legacySystemDaemon;
        description = ''
          Start a private per-user ydotoold service. This defaults to false
          when the legacy NixOS `services.codexComputerUse` module is enabled,
          so both modules can be used during a migration without starting two
          daemons.
        '';
      };

      socket = lib.mkOption {
        type = lib.types.str;
        default = if legacySystemDaemon then "/run/ydotoold/socket" else defaultSocket;
        example = "/run/user/1000/codex-computer-use/ydotool.sock";
        description = ''
          Absolute path used by ydotoold and exported as `YDOTOOL_SOCKET`.
          When the legacy NixOS Computer Use module is enabled, this defaults
          to its system socket. Otherwise it is a private socket in the
          Home Manager user's state directory.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "programs.codexComputerUse" pkgs lib.platforms.linux)
      {
        assertion = lib.hasPrefix "/" cfg.ydotoold.socket;
        message = "programs.codexComputerUse.ydotoold.socket must be an absolute path";
      }
    ];

    home.packages = [
      cfg.atSpiPackage
      cfg.ydotoolPackage
    ];

    # The AT-SPI bus is activated through D-Bus, while its user unit is still
    # useful to systemd user sessions that discover it through the unit path.
    dbus.packages = [ cfg.atSpiPackage ];
    systemd.user.packages = [ cfg.atSpiPackage ];

    home.sessionVariables.YDOTOOL_SOCKET = cfg.ydotoold.socket;
    systemd.user.sessionVariables.YDOTOOL_SOCKET = cfg.ydotoold.socket;

    # NixOS exports these values when its AT-SPI module is disabled. Remove
    # them from shell sessions so the Home Manager runtime can re-enable the
    # accessibility bridge without requiring the legacy system module.
    home.sessionVariablesExtra = lib.mkAfter ''
      unset NO_AT_BRIDGE
      unset GTK_A11Y
    '';

    systemd.user.services.ydotoold = lib.mkIf cfg.ydotoold.enable {
      Unit = {
        Description = "ydotoold - backend for Codex Computer Use";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg (builtins.dirOf cfg.ydotoold.socket)}";
        ExecStart = escapeSystemdExecArgs [
          (lib.getExe' cfg.ydotoolPackage "ydotoold")
          "--socket-path=${cfg.ydotoold.socket}"
          "--socket-perm=0600"
        ];
        Environment = [ "YDOTOOL_SOCKET=${cfg.ydotoold.socket}" ];
        # ydotoold can receive a clean SIGTERM when the graphical user target
        # is refreshed. Restart it in that case as well; otherwise the socket
        # remains on disk while all keyboard and scroll actions silently lose
        # their only Wayland fallback.
        Restart = "always";
        RestartSec = "1s";
        UMask = "0077";
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
