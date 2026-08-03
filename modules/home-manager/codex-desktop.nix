{
  self,
  codex-desktop-linux,
}:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.codexDesktopLinux;
  system = pkgs.stdenv.hostPlatform.system;
  defaultPackage = self.packages.${system}.codex-desktop.override {
    enableComputerUseUi = cfg.computerUseUi.enable;
    linuxFeatureIds =
      cfg.linuxFeatures ++ lib.optional cfg.remoteMobileControl.enable "remote-mobile-control";
  };
in
{
  imports = [
    codex-desktop-linux.homeManagerModules.default
    self.homeManagerModules.codexComputerUseHyprland
  ];

  programs.codexDesktopLinux = {
    cliPackage = lib.mkDefault self.packages.${system}.codex;
    package = lib.mkDefault defaultPackage;
  };
}
