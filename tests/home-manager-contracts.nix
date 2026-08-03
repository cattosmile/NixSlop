{
  self,
  pkgs,
  home-manager,
}:

let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  legacyModuleLib = lib.extend (
    _final: _previous: {
      hm.dag.entryAfter = after: data: { inherit after data; };
    }
  );

  baseModule = {
    home = {
      username = "module-test";
      homeDirectory = "/home/module-test";
      stateVersion = "26.05";
      enableNixpkgsReleaseCheck = false;
    };
  };

  mkHome =
    extraModules:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [ baseModule ] ++ extraModules;
    };

  packagePaths = packages: map (package: package.outPath) packages;
  packageCount = package: packages: lib.count (path: path == package.outPath) (packagePaths packages);

  customCodexPackage =
    (pkgs.writeShellScriptBin "codex" ''
      exec ${pkgs.coreutils}/bin/true "$@"
    '').overrideAttrs
      (_previous: {
        pname = "codex";
        version = "999.0.0";
      });
  customCodexOmxPackage = self.packages.${system}.oh-my-codex.override {
    codex = customCodexPackage;
  };
  explicitOmxPackage = pkgs.writeShellScriptBin "omx" ''
    exec ${pkgs.coreutils}/bin/true "$@"
  '';

  legacyOpenCodeEval = mkHome [
    self.homeManagerModules.openCode
    {
      programs.openCode.enable = true;
    }
  ];
  legacyOpenCode = legacyOpenCodeEval.config;

  legacyOpenCodeWithoutNative =
    (lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        self.homeManagerModules.openCode
        (
          { lib, ... }:
          {
            options.home.packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
            };
            config.programs.openCode.enable = true;
          }
        )
      ];
    }).config;

  nativeOpenCodeEval = mkHome [
    self.homeManagerModules.openCode
    {
      programs.opencode = {
        enable = true;
        settings = {
          model = "nixslop-contract-model";
          autoupdate = false;
        };
        context = "NixSlop OpenCode contract\n";
      };
    }
  ];
  nativeOpenCode = nativeOpenCodeEval.config;

  kimiEval = mkHome [
    self.homeManagerModules.kimiCode
    {
      programs.kimiCode = {
        enable = true;
        settings = {
          default_model = "kimi-code/k3";
          telemetry = false;
        };
      };
    }
  ];
  kimi = kimiEval.config;
  kimiConfigSource = kimi.home.file.".kimi-code/config.toml".source;

  kimiEmpty =
    (mkHome [
      self.homeManagerModules.kimiCode
      {
        programs.kimiCode.enable = true;
      }
    ]).config;

  codexOmxSetupEval = mkHome [
    self.homeManagerModules.codexOmx
    {
      programs.codexOmx = {
        enable = true;
        setupPlugin = true;
      };
    }
  ];
  codexOmxSetup = codexOmxSetupEval.config;
  codexOmxActivation = codexOmxSetup.home.activation.refreshOhMyCodexPlugin;

  codexOmxWithoutNative =
    (legacyModuleLib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        self.homeManagerModules.codexOmx
        (
          { lib, ... }:
          {
            options = {
              assertions = lib.mkOption {
                type = lib.types.listOf lib.types.anything;
                default = [ ];
              };
              home = {
                homeDirectory = lib.mkOption { type = lib.types.str; };
                packages = lib.mkOption {
                  type = lib.types.listOf lib.types.package;
                  default = [ ];
                };
                activation = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
              };
            };
            config = {
              home.homeDirectory = "/home/module-test";
              programs.codexOmx = {
                enable = true;
                setupPlugin = true;
              };
            };
          }
        )
      ];
    }).config;

  codexOmxNoSetupLegacy =
    (mkHome [
      self.homeManagerModules.codexOmx
      {
        programs.codexOmx = {
          enable = true;
          setupPlugin = false;
        };
      }
    ]).config;

  codexOmxDeclarativeEval = mkHome [
    self.homeManagerModules.codexOmx
    {
      programs = {
        codexOmx = {
          enable = true;
          setupPlugin = false;
        };
        codex = {
          enable = true;
          settings = {
            model = "nixslop-contract-model";
            approval_policy = "never";
          };
          context = "NixSlop Codex contract\n";
        };
      };
    }
  ];
  codexOmxDeclarative = codexOmxDeclarativeEval.config;

  codexOmxCustomCodex =
    (mkHome [
      self.homeManagerModules.codexOmx
      {
        programs.codexOmx = {
          enable = true;
          setupPlugin = false;
          codexPackage = customCodexPackage;
        };
        programs.codex.enable = true;
      }
    ]).config;

  codexOmxNativeNull =
    (mkHome [
      self.homeManagerModules.codexOmx
      {
        programs.codexOmx = {
          enable = true;
          setupPlugin = false;
        };
        programs.codex = {
          enable = true;
          package = null;
        };
      }
    ]).config;

  codexOmxExplicitPackage =
    (mkHome [
      self.homeManagerModules.codexOmx
      {
        programs.codexOmx = {
          enable = true;
          setupPlugin = false;
          ohMyCodexPackage = explicitOmxPackage;
        };
      }
    ]).config;

  declarativePlugin = builtins.head codexOmxDeclarative.programs.codex.plugins;
  declarativePluginCacheFiles = lib.filter (
    name: lib.hasPrefix ".codex/plugins/cache/home-manager/oh-my-codex/" name
  ) (builtins.attrNames codexOmxDeclarative.home.file);
  declarativePluginCacheFile = builtins.head declarativePluginCacheFiles;

  invalidMutableAndDeclarative = builtins.tryEval (
    builtins.deepSeq
      (mkHome [
        self.homeManagerModules.codexOmx
        {
          programs.codexOmx = {
            enable = true;
            setupPlugin = true;
          };
          programs.codex.enable = true;
        }
      ]).activationPackage.drvPath
      true
  );

  hyprlandBase = {
    programs.codexDesktopLinux.enable = true;
    wayland.windowManager.hyprland = {
      enable = true;
      configType = "lua";
      settings.input.kb_layout = "de";
    };
  };

  aggregateEval = mkHome [
    self.homeManagerModules.default
    hyprlandBase
  ];
  aggregate = aggregateEval.config;

  aggregateAlias =
    (mkHome [
      self.homeManagerModules.nixslop
      hyprlandBase
    ]).config;

  hyprlandOptOut =
    (mkHome [
      self.homeManagerModules.codexDesktop
      (lib.recursiveUpdate hyprlandBase {
        programs.codexComputerUseHyprland.enable = false;
      })
    ]).config;

  hyprlangConfig =
    (mkHome [
      self.homeManagerModules.codexDesktop
      (lib.recursiveUpdate hyprlandBase {
        wayland.windowManager.hyprland.configType = "hyprlang";
      })
    ]).config;

  hyprlandWithoutConfigType =
    (lib.evalModules {
      modules = [
        self.homeManagerModules.codexComputerUseHyprland
        (
          { lib, ... }:
          {
            options = {
              programs.codexDesktopLinux.enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              wayland.windowManager.hyprland = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                settings.device = lib.mkOption {
                  type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
                  default = [ ];
                };
              };
            };
            config = {
              programs.codexDesktopLinux.enable = true;
              wayland.windowManager.hyprland.enable = true;
            };
          }
        )
      ];
    }).config;

  expectedVirtualDevice = [
    {
      name = "ydotoold-virtual-device";
      kb_layout = "us";
      kb_variant = "";
      kb_options = "";
    }
  ];

  aggregateProjection = config: {
    codexDesktopEnabled = config.programs.codexDesktopLinux.enable;
    physicalLayout = config.wayland.windowManager.hyprland.settings.input.kb_layout;
    virtualDevices = config.wayland.windowManager.hyprland.settings.device;
  };

  expectedKimiConfig = pkgs.writeText "expected-kimi-code-config.toml" ''
    default_model = "kimi-code/k3"
    telemetry = false
  '';

  generatedFiles = pkgs.runCommand "nixslop-home-manager-generated-file-contracts" { } ''
    cmp ${kimiConfigSource} ${expectedKimiConfig}
    grep -Fq '"model": "nixslop-contract-model"' ${
      nativeOpenCode.xdg.configFile."opencode/opencode.json".source
    }
    codex_config=${codexOmxDeclarative.home.file.".codex/config.toml".source}
    grep -Fq 'model = "nixslop-contract-model"' "$codex_config"
    grep -Fq 'plugins = true' "$codex_config"
    grep -Fq '[plugins."oh-my-codex@home-manager"]' "$codex_config"
    marketplace=${codexOmxDeclarative.home.file.".agents/plugins/marketplace.json".source}
    grep -Fq '"name": "oh-my-codex"' "$marketplace"
    grep -Fq '.codex/plugins/cache/home-manager/oh-my-codex/' "$marketplace"
    grep -Fq '${customCodexPackage}/bin' ${customCodexOmxPackage}/bin/omx
    touch "$out"
  '';

  assertions =
    assert legacyOpenCode.programs.opencode.enable;
    assert legacyOpenCode.programs.opencode.package.outPath == self.packages.${system}.opencode.outPath;
    assert packageCount self.packages.${system}.opencode legacyOpenCode.home.packages == 1;
    assert packageCount self.packages.${system}.opencode legacyOpenCodeWithoutNative.home.packages == 1;
    assert nativeOpenCode.programs.opencode.package.outPath == self.packages.${system}.opencode.outPath;
    assert packageCount self.packages.${system}.opencode nativeOpenCode.home.packages == 1;
    assert builtins.hasAttr "opencode/opencode.json" nativeOpenCode.xdg.configFile;
    assert nativeOpenCode.xdg.configFile."opencode/AGENTS.md".text == "NixSlop OpenCode contract\n";
    assert packageCount self.packages.${system}.kimi-code kimi.home.packages == 1;
    assert
      lib.filter (name: lib.hasPrefix ".kimi-code/" name) (builtins.attrNames kimi.home.file) == [
        ".kimi-code/config.toml"
      ];
    assert !(builtins.hasAttr ".kimi-code/config.toml" kimiEmpty.home.file);
    assert !codexOmxSetup.programs.codex.enable;
    assert
      codexOmxSetup.programs.codexOmx.ohMyCodexPackage.outPath
      == self.packages.${system}.oh-my-codex.outPath;
    assert packageCount self.packages.${system}.codex codexOmxSetup.home.packages == 1;
    assert packageCount self.packages.${system}.oh-my-codex codexOmxSetup.home.packages == 1;
    assert packageCount pkgs.tmux codexOmxSetup.home.packages == 1;
    assert !(builtins.hasAttr ".codex/config.toml" codexOmxSetup.home.file);
    assert codexOmxActivation.after == [ "writeBoundary" ];
    assert lib.hasInfix "--unset=OMX_ROOT" codexOmxActivation.data;
    assert lib.hasInfix ''CODEX_HOME="/home/module-test/.codex"'' codexOmxActivation.data;
    assert lib.hasInfix "omx setup --plugin --force --scope user" codexOmxActivation.data;
    assert !(builtins.hasAttr "codex" codexOmxWithoutNative.programs);
    assert lib.all (entry: entry.assertion) codexOmxWithoutNative.assertions;
    assert packageCount self.packages.${system}.codex codexOmxWithoutNative.home.packages == 1;
    assert packageCount self.packages.${system}.oh-my-codex codexOmxWithoutNative.home.packages == 1;
    assert packageCount pkgs.tmux codexOmxWithoutNative.home.packages == 1;
    assert lib.hasInfix "omx setup --plugin --force --scope user"
      codexOmxWithoutNative.home.activation.refreshOhMyCodexPlugin.data;
    assert !codexOmxNoSetupLegacy.programs.codex.enable;
    assert packageCount self.packages.${system}.codex codexOmxNoSetupLegacy.home.packages == 1;
    assert packageCount self.packages.${system}.oh-my-codex codexOmxNoSetupLegacy.home.packages == 1;
    assert packageCount pkgs.tmux codexOmxNoSetupLegacy.home.packages == 1;
    assert !(builtins.hasAttr "refreshOhMyCodexPlugin" codexOmxNoSetupLegacy.home.activation);
    assert codexOmxDeclarative.programs.codex.enable;
    assert codexOmxDeclarative.programs.codex.package.outPath == self.packages.${system}.codex.outPath;
    # Keep the plugin as a derivation. A string containing a foreign-system
    # store path makes Home Manager's directory assertion realise that package
    # during `nix flake check --all-systems --no-build`.
    assert builtins.length codexOmxDeclarative.programs.codex.plugins == 1;
    assert lib.isDerivation declarativePlugin;
    assert packageCount self.packages.${system}.codex codexOmxDeclarative.home.packages == 1;
    assert packageCount self.packages.${system}.oh-my-codex codexOmxDeclarative.home.packages == 1;
    assert packageCount pkgs.tmux codexOmxDeclarative.home.packages == 1;
    assert builtins.hasAttr ".codex/config.toml" codexOmxDeclarative.home.file;
    assert codexOmxDeclarative.home.file.".codex/AGENTS.md".text == "NixSlop Codex contract\n";
    assert !(builtins.hasAttr "refreshOhMyCodexPlugin" codexOmxDeclarative.home.activation);
    assert builtins.length declarativePluginCacheFiles == 1;
    assert
      codexOmxDeclarative.home.file.${declarativePluginCacheFile}.source.outPath
      == declarativePlugin.outPath;
    assert builtins.hasAttr ".agents/plugins/marketplace.json" codexOmxDeclarative.home.file;
    assert builtins.hasAttr "cleanCodexPluginCache" codexOmxDeclarative.home.activation;
    assert codexOmxCustomCodex.programs.codex.package.outPath == customCodexPackage.outPath;
    assert
      codexOmxCustomCodex.programs.codexOmx.ohMyCodexPackage.outPath == customCodexOmxPackage.outPath;
    assert packageCount customCodexPackage codexOmxCustomCodex.home.packages == 1;
    assert packageCount self.packages.${system}.codex codexOmxCustomCodex.home.packages == 0;
    assert codexOmxNativeNull.programs.codex.package == null;
    assert packageCount self.packages.${system}.codex codexOmxNativeNull.home.packages == 1;
    assert
      codexOmxNativeNull.programs.codexOmx.ohMyCodexPackage.outPath
      == self.packages.${system}.oh-my-codex.outPath;
    assert
      codexOmxExplicitPackage.programs.codexOmx.ohMyCodexPackage.outPath == explicitOmxPackage.outPath;
    assert packageCount explicitOmxPackage codexOmxExplicitPackage.home.packages == 1;
    assert !invalidMutableAndDeclarative.success;
    assert lib.hasAttrByPath [ "programs" "openCode" "enable" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "kimiCode" "settings" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "codexOmx" "setupPlugin" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "codexDesktopLinux" "enable" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "codexComputerUseHyprland" "enable" ] aggregateEval.options;
    # `homeManagerModules.nixslop` is a public behavioral alias for the
    # aggregate. Compare evaluated values, never the module functions.
    assert aggregateProjection aggregateAlias == aggregateProjection aggregate;
    assert
      aggregate.programs.codexDesktopLinux.package.outPath
      == self.packages.${system}.codex-desktop.outPath;
    assert
      aggregate.programs.codexDesktopLinux.cliPackage.outPath == self.packages.${system}.codex.outPath;
    assert aggregate.wayland.windowManager.hyprland.settings.input.kb_layout == "de";
    assert aggregate.wayland.windowManager.hyprland.settings.device == expectedVirtualDevice;
    assert hyprlandOptOut.wayland.windowManager.hyprland.settings.input.kb_layout == "de";
    assert
      lib.attrByPath [ "wayland" "windowManager" "hyprland" "settings" "device" ] [ ] hyprlandOptOut
      == [ ];
    assert hyprlangConfig.wayland.windowManager.hyprland.settings.input.kb_layout == "de";
    assert
      lib.attrByPath [ "wayland" "windowManager" "hyprland" "settings" "device" ] [ ] hyprlangConfig
      == [ ];
    assert hyprlandWithoutConfigType.wayland.windowManager.hyprland.settings.device == [ ];
    true;
in
{
  inherit assertions generatedFiles;
}
