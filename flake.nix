{
  description = "NixSlop - fast-moving developer tools as Home Manager modules";

  nixConfig = {
    extra-substituters = [ "https://nixslop.cachix.org?priority=30" ];
    extra-trusted-public-keys = [
      "nixslop.cachix.org-1:Y41flUqIXb+Qx7D6hiugUE17RG4EkLaBn3UlVXc1oE8="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default-linux";
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
    opencode.url = "github:anomalyco/opencode";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      codex-desktop-linux,
      opencode,
      home-manager,
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

      nixslopHomeManagerModule = import ./modules/home-manager/default.nix { inherit self; };
      codexComputerUseModule = import ./modules/nixos/codex-computer-use.nix;
    in
    {
      packages = eachSystem (
        system:
        import ./packages {
          pkgs = pkgsFor system;
          inherit codex-desktop-linux opencode;
        }
      );

      homeManagerModules = {
        openCode = import ./modules/home-manager/open-code.nix { inherit self; };
        codexDesktop = import ./modules/home-manager/codex-desktop.nix {
          inherit self codex-desktop-linux;
        };
        codexComputerUseHyprland = import ./modules/home-manager/codex-computer-use-hyprland.nix;
        kimiCode = import ./modules/home-manager/kimi-code.nix { inherit self; };
        codexOmx = import ./modules/home-manager/codex-omx.nix { inherit self; };
        ccSwitch = import ./modules/home-manager/cc-switch.nix { inherit self; };
        default = nixslopHomeManagerModule;
        nixslop = nixslopHomeManagerModule;
      };

      nixosModules = {
        default = codexComputerUseModule;
        codexComputerUse = codexComputerUseModule;
      };

      checks = eachSystem (
        system:
        import ./nix/checks.nix {
          inherit self home-manager;
          pkgs = pkgsFor system;
        }
      );

      devShells = eachSystem (system: import ./nix/dev-shells.nix { pkgs = pkgsFor system; });

      formatter = eachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        if pkgs ? nixfmt-tree then
          pkgs.nixfmt-tree
        else if pkgs ? nixfmt-rfc-style then
          pkgs.nixfmt-rfc-style
        else
          pkgs.nixfmt
      );
    };
}
