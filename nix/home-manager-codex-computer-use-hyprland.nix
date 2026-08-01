{
  config,
  lib,
  ...
}:

let
  cfg = lib.attrByPath [ "programs" "codexComputerUseHyprland" ] { enable = true; } config;
  codexDesktopEnabled = lib.attrByPath [ "programs" "codexDesktopLinux" "enable" ] false config;
  hyprlandEnabled = lib.attrByPath [ "wayland" "windowManager" "hyprland" "enable" ] false config;
  hyprlandConfigType = lib.attrByPath [ "wayland" "windowManager" "hyprland" "configType" ] "lua" config;
in
{
  options.programs.codexComputerUseHyprland.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Configure the US keymap for the Hyprland ydotool virtual keyboard used by Codex Computer Use.";
  };

  config = lib.mkIf (
    cfg.enable
    && codexDesktopEnabled
    && hyprlandEnabled
    && hyprlandConfigType == "lua"
  ) {
    # Home Manager renders top-level `settings.device` entries as hl.device()
    # calls in Lua mode. Keep the physical keyboard's normal layout untouched.
    wayland.windowManager.hyprland.settings.device = lib.mkAfter [
      {
        name = "ydotoold-virtual-device";
        kb_layout = "us";
        kb_variant = "";
        kb_options = "";
      }
    ];
  };
}
