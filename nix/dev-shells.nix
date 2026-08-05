{ pkgs }:

{
  default = pkgs.mkShell {
    packages = with pkgs; [
      actionlint
      dbus
      gh
      git
      nix-prefetch-github
      python3
      xvfb-run
    ];
  };
}
