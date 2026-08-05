{
  self,
  pkgs,
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  packages = self.packages.${system};
  packageNames = builtins.attrNames packages;
  expectedPackageNames = [
    "cc-switch"
    "codex"
    "codex-computer-use-linux"
    "codex-desktop"
    "codex-desktop-computer-use-ui"
    "codex-desktop-computer-use-ui-remote-mobile-control"
    "codex-desktop-remote-mobile-control"
    "kimi-code"
    "oh-my-codex"
    "opencode"
  ];

  computerUseUiOverride = packages.codex-desktop.override {
    enableComputerUseUi = true;
  };
  remoteMobileControlOverride = packages.codex-desktop.override {
    linuxFeatureIds = [ "remote-mobile-control" ];
  };
  allArgumentsOverride = packages.codex-desktop.override {
    enableComputerUseUi = true;
    linuxFeatureIds = [ "remote-mobile-control" ];
    linuxFeaturesConfigOverride.enabled = [ "remote-mobile-control" ];
  };
  configOnlyRemoteOverride = packages.codex-desktop.override {
    linuxFeaturesConfigOverride.enabled = [ "remote-mobile-control" ];
  };
  configClearsRawFeaturesOverride = packages.codex-desktop.override {
    linuxFeatureIds = [ "remote-mobile-control" ];
    linuxFeaturesConfigOverride.enabled = [ ];
  };
in
assert packageNames == expectedPackageNames;
assert pkgs.lib.isDerivation computerUseUiOverride;
assert pkgs.lib.isDerivation remoteMobileControlOverride;
assert pkgs.lib.isDerivation allArgumentsOverride;
assert computerUseUiOverride.outPath == packages.codex-desktop-computer-use-ui.outPath;
assert remoteMobileControlOverride.outPath == packages.codex-desktop-remote-mobile-control.outPath;
assert configOnlyRemoteOverride.outPath == packages.codex-desktop-remote-mobile-control.outPath;
assert configClearsRawFeaturesOverride.outPath == packages.codex-desktop.outPath;
true
