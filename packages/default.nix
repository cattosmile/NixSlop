{
  pkgs,
  codex-desktop-linux,
}:

let
  codex = pkgs.callPackage ./codex/package.nix { };
  chatgptDesktop = pkgs.callPackage ./chatgpt-desktop/package.nix {
    inherit codex-desktop-linux;
  };
in
{
  inherit codex;

  chatgpt-desktop = chatgptDesktop;

  # Keep the historical names as aliases while consumers migrate to the
  # unified official ChatGPT/Codex desktop package.
  codex-computer-use-linux = chatgptDesktop;
  codex-desktop = chatgptDesktop;
  codex-desktop-computer-use-ui = chatgptDesktop.override {
    enableComputerUseUi = true;
  };
  codex-desktop-remote-mobile-control = chatgptDesktop.override {
    linuxFeatureIds = [ "remote-mobile-control" ];
  };
  codex-desktop-computer-use-ui-remote-mobile-control = chatgptDesktop.override {
    enableComputerUseUi = true;
    linuxFeatureIds = [ "remote-mobile-control" ];
  };
  oh-my-codex = pkgs.callPackage ./oh-my-codex/package.nix { inherit codex; };
}
