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
          upstreamCodexDesktop = codex-desktop-linux.packages.${system}.codex-desktop;
          computerUseSource = pkgs.runCommandLocal "nixslop-computer-use-linux-source" {
            nativeBuildInputs = [ pkgs.patch ];
          } ''
            mkdir -p "$out"
            cp ${codex-desktop-linux}/Cargo.lock "$out/Cargo.lock"
            cat > "$out/Cargo.toml" <<'EOF'
            [workspace]
            members = ["computer-use-linux"]
            resolver = "2"
            EOF
            cp -R ${codex-desktop-linux}/computer-use-linux "$out/computer-use-linux"
            chmod -R u+w "$out"
            patch -d "$out" -p1 < ${./packages/codex-desktop/computer-use.patch}
          '';
          computerUseBinaries = pkgs.rustPlatform.buildRustPackage {
            pname = "nixslop-codex-computer-use-linux-binaries";
            version = "0.1.2-linux-alpha2";
            src = computerUseSource;

            cargoLock = {
              lockFile = "${codex-desktop-linux}/Cargo.lock";
            };

            buildAndTestSubdir = "computer-use-linux";
            cargoBuildFlags = [
              "-p"
              "codex-computer-use-linux"
              "--bins"
            ];
            doCheck = false;

            installPhase = ''
              runHook preInstall
              release_dir="target/''${CARGO_BUILD_TARGET:-${pkgs.stdenv.hostPlatform.rust.rustcTarget}}/release"
              if [ ! -d "$release_dir" ]; then
                release_dir="target/release"
              fi
              install -Dm0755 "$release_dir/codex-computer-use-linux" "$out/bin/codex-computer-use-linux"
              install -Dm0755 "$release_dir/codex-computer-use-cosmic" "$out/bin/codex-computer-use-cosmic"
              install -Dm0755 "$release_dir/codex-chrome-extension-host" "$out/bin/codex-chrome-extension-host"
              runHook postInstall
            '';
          };
          customizeCodexDesktop = package: package.overrideAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              plugin_dir="$out/opt/codex-desktop/resources/plugins/openai-bundled/plugins/computer-use"
              test -f "$plugin_dir/assets/app-icon.png"
              install -Dm0644 ${./packages/codex-desktop/computer-use-plugin.json} "$plugin_dir/.codex-plugin/plugin.json"
              install -Dm0755 ${computerUseBinaries}/bin/codex-computer-use-linux "$plugin_dir/bin/codex-computer-use-linux"
              install -Dm0755 ${computerUseBinaries}/bin/codex-computer-use-cosmic "$plugin_dir/bin/codex-computer-use-cosmic"
              install -Dm0755 ${computerUseBinaries}/bin/codex-chrome-extension-host "$plugin_dir/bin/codex-chrome-extension-host"
            '';
          });
          codexDesktop = pkgs.lib.makeOverridable (
            {
              enableComputerUseUi ? false,
              linuxFeatureIds ? [ ],
              linuxFeaturesConfigOverride ? null,
            }:
            customizeCodexDesktop (
              upstreamCodexDesktop.override {
                inherit enableComputerUseUi linuxFeatureIds linuxFeaturesConfigOverride;
              }
            )
          ) { };
        in
        {
          inherit codex;
          codex-computer-use-linux = computerUseBinaries;
          codex-desktop = codexDesktop;
          codex-desktop-computer-use-ui = codexDesktop.override { enableComputerUseUi = true; };
          codex-desktop-remote-mobile-control = codexDesktop.override {
            linuxFeatureIds = [ "remote-mobile-control" ];
          };
          codex-desktop-computer-use-ui-remote-mobile-control = codexDesktop.override {
            enableComputerUseUi = true;
            linuxFeatureIds = [ "remote-mobile-control" ];
          };
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
            linuxFeatureIds = cfg.linuxFeatures ++ lib.optional cfg.remoteMobileControl.enable "remote-mobile-control";
          };
        in
        {
          imports = [ codex-desktop-linux.homeManagerModules.default ];

          programs.codexDesktopLinux = {
            cliPackage = lib.mkDefault self.packages.${system}.codex;
            package = lib.mkDefault defaultPackage;
          };
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
                  ${pkgs.coreutils}/bin/env \
                    --unset=OMX_ROOT \
                    --unset=OMX_STATE_ROOT \
                    HOME="${config.home.homeDirectory}" \
                    CODEX_HOME="${config.home.homeDirectory}/.codex" \
                    ${omxPackage}/bin/omx setup --plugin --force --scope user
                fi
              ''
            );
          };
        };

      nixosModules = rec {
        default = codexComputerUse;
        codexComputerUse = import ./nix/nixos-module.nix;
      };

      checks = eachSystem (
        system:
        let
          pkgs = pkgsFor system;
          moduleContracts = import ./tests/module-contracts.nix { inherit self pkgs; };
          codexDesktopComputerUse = self.packages.${system}.codex-desktop;
        in
        {
          module-contracts =
            assert moduleContracts;
            pkgs.runCommand "nixslop-module-contracts" { } ''
              touch $out
            '';

          codex-desktop-computer-use = pkgs.runCommand "nixslop-codex-desktop-computer-use" { } ''
            plugin="${codexDesktopComputerUse}/opt/codex-desktop/resources/plugins/openai-bundled/plugins/computer-use"
            test -f "$plugin/.codex-plugin/plugin.json"
            test -x "$plugin/bin/codex-computer-use-linux"
            test -x "$plugin/bin/codex-computer-use-cosmic"
            test -x "$plugin/bin/codex-chrome-extension-host"
            grep -Fq '"hyprland"' "$plugin/.codex-plugin/plugin.json"
            grep -Fq '"grim"' "$plugin/.codex-plugin/plugin.json"
            grep -Fq '"ydotool"' "$plugin/.codex-plugin/plugin.json"
            if grep -Fq '"gnome"' "$plugin/.codex-plugin/plugin.json"; then
              echo "unexpected GNOME keyword in the packaged Computer Use plugin" >&2
              exit 1
            fi
            touch $out
          '';
        }
      );

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
