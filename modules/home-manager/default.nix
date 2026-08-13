{ self }:

{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.nixslop;
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
        default = false;
        description = ''
          Configure the legacy Hyprland keymap for the ydotool Computer Use
          virtual device. The official ChatGPT Desktop app does not need this.
        '';
      };
    };

    computerUse.enable = lib.mkEnableOption ''
      the legacy ydotool/AT-SPI Linux Computer Use runtime. The official
      ChatGPT Desktop app bundles its own native Computer Use backend, so this
      is normally not needed.
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
