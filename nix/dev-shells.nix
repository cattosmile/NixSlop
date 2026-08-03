{ pkgs }:

{
  default = pkgs.mkShell {
    packages = with pkgs; [
      actionlint
      gh
      git
      nix-prefetch-github
      python3
    ];
  };
}
