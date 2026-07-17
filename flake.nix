{
  description = "NixSlop - fast-moving app packages for NixOS";

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
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      codex-desktop-linux,
      opencode,
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);
      pkgsFor =
        system:
        import nixpkgs {
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
        let
          codex = pkgs.callPackage ./packages/codex/package.nix { };
        in
        {
          inherit codex;
          codex-desktop = codex-desktop-linux.packages.${system}.codex-desktop;
          kimi-code = pkgs.callPackage ./packages/kimi-code/package.nix { };
          opencode = opencode.packages.${system}.opencode;
          oh-my-codex = pkgs.callPackage ./packages/oh-my-codex/package.nix { inherit codex; };
        }
      );

      homeManagerModules.openCode =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.openCode;
          system = pkgs.stdenv.hostPlatform.system;
        in
        {
          options.programs.openCode = {
            enable = lib.mkEnableOption "OpenCode CLI";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${system}.opencode;
              defaultText = lib.literalExpression "inputs.nixslop.packages.${pkgs.stdenv.hostPlatform.system}.opencode";
              description = "OpenCode CLI package to install.";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];
          };
        };

      homeManagerModules.codexDesktop =
        {
          lib,
          pkgs,
          ...
        }:
        let
          system = pkgs.stdenv.hostPlatform.system;
        in
        {
          imports = [ codex-desktop-linux.homeManagerModules.default ];

          programs.codexDesktopLinux.cliPackage = lib.mkDefault self.packages.${system}.codex;
        };

      homeManagerModules.kimiCode =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.kimiCode;
          system = pkgs.stdenv.hostPlatform.system;
        in
        {
          options.programs.kimiCode = {
            enable = lib.mkEnableOption "Kimi Code CLI";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${system}.kimi-code;
              defaultText = lib.literalExpression "inputs.nixslop.packages.${pkgs.stdenv.hostPlatform.system}.kimi-code";
              description = "Kimi Code CLI package to install.";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];
          };
        };

      homeManagerModules.codexOmx =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.codexOmx;
          system = pkgs.stdenv.hostPlatform.system;
          codexPackage = cfg.codexPackage;
          omxPackage = cfg.ohMyCodexPackage;
          omxPluginRoot = "${omxPackage}/lib/node_modules/oh-my-codex";
        in
        {
          options.programs.codexOmx = {
            enable = lib.mkEnableOption "Codex CLI with oh-my-codex integration";

            codexPackage = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${system}.codex;
              defaultText = lib.literalExpression "inputs.nixslop.packages.${pkgs.stdenv.hostPlatform.system}.codex";
              description = "Codex package to install and expose to oh-my-codex.";
            };

            ohMyCodexPackage = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${system}.oh-my-codex;
              defaultText = lib.literalExpression "inputs.nixslop.packages.${pkgs.stdenv.hostPlatform.system}.oh-my-codex";
              description = "oh-my-codex package to install and register as a Codex plugin.";
            };

            setupPlugin = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Run idempotent oh-my-codex plugin setup during Home Manager activation.";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [
              codexPackage
              omxPackage
              pkgs.tmux
            ];

            home.activation.refreshOhMyCodexPlugin = lib.mkIf cfg.setupPlugin (
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                expected_source='source = "${omxPluginRoot}"'
                expected_command='${omxPluginRoot}/dist/cli/omx.js'
                config_file="${config.home.homeDirectory}/.codex/config.toml"
                cache_base="${config.home.homeDirectory}/.codex/plugins/cache/oh-my-codex-local/oh-my-codex"

                if ! grep -Fq "$expected_source" "$config_file" 2>/dev/null \
                  || ! grep -R -Fq "$expected_command" "$cache_base" 2>/dev/null; then
                  ${omxPackage}/bin/omx setup --plugin --force --scope user
                fi
              ''
            );
          };
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
