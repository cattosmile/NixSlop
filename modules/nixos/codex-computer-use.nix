{
  config,
  lib,
  ...
}:

let
  cfg = config.services.codexComputerUse;
in
{
  options.services.codexComputerUse = {
    enable = lib.mkEnableOption "the compositor-neutral Linux Computer Use runtime";

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "user";
      description = ''
        Optional user name to add to the ydotool group. Leave this null when
        the system manages group membership separately.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # AT-SPI2 is the accessibility bus used by the native Computer Use
    # backend. This does not enable GNOME Shell or select a GNOME session.
    services.gnome.at-spi2-core.enable = true;
    programs.ydotool.enable = true;

    users.users = lib.mkIf (cfg.user != null) {
      "${cfg.user}".extraGroups = lib.mkAfter [ "ydotool" ];
    };
  };
}
