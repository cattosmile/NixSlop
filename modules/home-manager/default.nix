{ self }:

{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.nixslop;
  hyprlandEnabled = lib.attrByPath [
    "wayland"
    "windowManager"
    "hyprland"
    "enable"
  ] false config;
in
{
  imports = [
    self.homeManagerModules.codexComputerUse
    self.homeManagerModules.codexDesktop
    self.homeManagerModules.codexOmx
  ];

  options.programs.nixslop = {
    codex.enable = lib.mkEnableOption ''
      the NixSlop Codex CLI integration. This currently uses the combined
      Codex/oh-my-codex Home Manager module.
    '';

    omx.enable = lib.mkEnableOption ''
      the NixSlop Codex/oh-my-codex integration. This is an equivalent
      selector for `codex.enable` while those components remain coupled.
    '';

    desktop = {
      enable = lib.mkEnableOption "NixSlop Codex Desktop";

      computerUseUi.enable = lib.mkEnableOption "the Codex Desktop Computer Use UI";

      remoteMobileControl.enable = lib.mkEnableOption "Codex Desktop Remote Mobile Control";

      hyprland.enable = lib.mkOption {
        type = lib.types.bool;
        default = hyprlandEnabled;
        description = ''
          Configure the Hyprland keymap for the ydotool Computer Use virtual
          device used by the NixSlop Linux plugin. This is enabled
          automatically when Home Manager's Hyprland module is enabled and can
          be set to false to opt out.
        '';
      };
    };

    computerUse.enable = lib.mkEnableOption ''
      the ydotool/AT-SPI fallback runtime used by the NixSlop Linux Computer Use
      plugin. The plugin can also use native uinput and Wayland capture paths.
    '';
  };

  config = {
    # The existing modules remain the implementation and compatibility
    # boundary. Weak defaults let users keep using their historical paths.
    programs.codexOmx.enable = lib.mkDefault (cfg.codex.enable || cfg.omx.enable);

    programs.codexDesktopLinux = {
      enable = lib.mkDefault cfg.desktop.enable;
      computerUseUi.enable = lib.mkDefault cfg.desktop.computerUseUi.enable;
      remoteMobileControl.enable = lib.mkDefault cfg.desktop.remoteMobileControl.enable;
    };

    programs.codexComputerUse.enable = lib.mkDefault cfg.computerUse.enable;
    programs.codexComputerUseHyprland.enable = lib.mkDefault (
      cfg.computerUse.enable && cfg.desktop.hyprland.enable
    );
  };
}
