{
  description = "NixSlop - fast-moving app packages for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default-linux";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      packages = eachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        rec {
          codex = pkgs.callPackage ./packages/codex/package.nix { };
          default = codex;
        }
      );

      apps = eachSystem (
        system: {
          codex = {
            type = "app";
            program = "${self.packages.${system}.codex}/bin/codex";
          };
          default = self.apps.${system}.codex;
        }
      );

      overlays.default = final: _prev: {
        nixslop = self.packages.${final.stdenv.hostPlatform.system};
        codex-latest = self.packages.${final.stdenv.hostPlatform.system}.codex;
      };

      devShells = eachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              git
              nix-prefetch-github
              python3
            ];
          };
        }
      );
    };
}
