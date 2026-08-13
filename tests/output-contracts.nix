{
  self,
  pkgs,
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  packages = self.packages.${system};
  packageNames = builtins.attrNames packages;
  expectedPackageNames = [
    "chatgpt-desktop"
    "codex"
    "codex-computer-use-linux"
    "codex-desktop"
    "codex-desktop-computer-use-ui"
    "codex-desktop-computer-use-ui-remote-mobile-control"
    "codex-desktop-remote-mobile-control"
    "oh-my-codex"
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
assert builtins.hasAttr "computerUseBinaries" computerUseUiOverride;
assert
  computerUseUiOverride.passthru.desktopContents.outPath
  == computerUseUiOverride.passthru.computerUseContents.outPath;
assert
  packages.chatgpt-desktop.passthru.desktopContents.outPath
  == packages.chatgpt-desktop.passthru.contents.outPath;
assert pkgs.lib.isDerivation remoteMobileControlOverride;
assert pkgs.lib.isDerivation allArgumentsOverride;
assert packages.chatgpt-desktop.outPath == packages.codex-desktop.outPath;
assert packages.chatgpt-desktop.outPath == packages.codex-computer-use-linux.outPath;
assert computerUseUiOverride.outPath == packages.codex-desktop-computer-use-ui.outPath;
assert remoteMobileControlOverride.outPath == packages.codex-desktop-remote-mobile-control.outPath;
assert configOnlyRemoteOverride.outPath == packages.codex-desktop-remote-mobile-control.outPath;
assert configClearsRawFeaturesOverride.outPath == packages.codex-desktop.outPath;
true
