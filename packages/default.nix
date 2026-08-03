{
  pkgs,
  codex-desktop-linux,
  opencode,
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  codex = pkgs.callPackage ./codex/package.nix { };
  codexDesktop = pkgs.callPackage ./codex-desktop/package.nix {
    codexDesktopLinux = codex-desktop-linux;
  };
in
{
  inherit codex;

  codex-computer-use-linux = codexDesktop.computerUseBinaries;
  codex-desktop = codexDesktop;
  codex-desktop-computer-use-ui = codexDesktop.override {
    enableComputerUseUi = true;
  };
  codex-desktop-remote-mobile-control = codexDesktop.override {
    linuxFeatureIds = [ "remote-mobile-control" ];
  };
  codex-desktop-computer-use-ui-remote-mobile-control = codexDesktop.override {
    enableComputerUseUi = true;
    linuxFeatureIds = [ "remote-mobile-control" ];
  };
  kimi-code = pkgs.callPackage ./kimi-code/package.nix { };
  opencode = opencode.packages.${system}.opencode;
  oh-my-codex = pkgs.callPackage ./oh-my-codex/package.nix { inherit codex; };
}
