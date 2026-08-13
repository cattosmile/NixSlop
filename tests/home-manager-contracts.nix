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

  codexComputerUseEval = mkHome [
    self.homeManagerModules.codexComputerUse
    {
      programs.codexComputerUse.enable = true;
    }
  ];
  codexComputerUse = codexComputerUseEval.config;

  legacyCodexComputerUse =
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        osConfig = {
          services.codexComputerUse.enable = true;
        };
      };
      modules = [
        baseModule
        self.homeManagerModules.codexComputerUse
        {
          programs.codexComputerUse.enable = true;
        }
      ];
    }).config;

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
  codexDefaultPluginsActivation = codexOmxSetup.home.activation.restoreCodexDefaultPlugins;

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

  centralFacade =
    (mkHome [
      self.homeManagerModules.default
      {
        programs.nixslop = {
          codex.enable = true;
          desktop = {
            enable = true;
            computerUseUi.enable = true;
            remoteMobileControl.enable = true;
          };
          computerUse.enable = true;
        };
        wayland.windowManager.hyprland = {
          enable = true;
          configType = "lua";
          settings.input.kb_layout = "de";
        };
      }
    ]).config;

  omxFacadeOnly =
    (mkHome [
      self.homeManagerModules.default
      {
        programs.nixslop.omx.enable = true;
      }
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

  ydotooldExecStart = lib.concatStringsSep " " codexComputerUse.systemd.user.services.ydotoold.Service.ExecStart;

  aggregateProjection = config: {
    codexDesktopEnabled = config.programs.codexDesktopLinux.enable;
    physicalLayout = config.wayland.windowManager.hyprland.settings.input.kb_layout;
    virtualDevices =
      lib.attrByPath [ "wayland" "windowManager" "hyprland" "settings" "device" ] [ ]
        config;
  };

  generatedFiles = pkgs.runCommand "nixslop-generated-file-contracts" { } ''
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
    assert codexOmxSetup.programs.codexOmx.restoreDefaultPlugins;
    assert
      codexDefaultPluginsActivation.after == [
        "writeBoundary"
        "refreshOhMyCodexPlugin"
      ];
    assert lib.hasInfix "plugin marketplace add" codexDefaultPluginsActivation.data;
    assert lib.hasInfix "documents@openai-primary-runtime" codexDefaultPluginsActivation.data;
    assert lib.hasInfix "spreadsheets@openai-primary-runtime" codexDefaultPluginsActivation.data;
    assert lib.hasInfix "presentations@openai-primary-runtime" codexDefaultPluginsActivation.data;
    assert lib.hasInfix "pdf@openai-primary-runtime" codexDefaultPluginsActivation.data;
    assert lib.hasInfix "template-creator@openai-primary-runtime" codexDefaultPluginsActivation.data;
    assert lib.hasInfix "outlook-calendar@openai-curated" codexDefaultPluginsActivation.data;
    assert lib.hasInfix "teams@openai-curated" codexDefaultPluginsActivation.data;
    assert lib.hasInfix "if [ -f \"$primary_runtime/.agents/plugins/marketplace.json\" ]"
      codexDefaultPluginsActivation.data;
    assert lib.hasInfix ''grep -Fq "[plugins.\"$plugin\"]"'' codexDefaultPluginsActivation.data;
    assert lib.hasInfix "continue" codexDefaultPluginsActivation.data;
    assert !lib.hasInfix "auth.json" codexDefaultPluginsActivation.data;
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
    assert !(builtins.hasAttr "restoreCodexDefaultPlugins" codexOmxDeclarative.home.activation);
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
    assert codexComputerUse.programs.codexComputerUse.enable;
    assert packageCount pkgs.at-spi2-core codexComputerUse.home.packages == 1;
    assert packageCount pkgs.ydotool codexComputerUse.home.packages == 1;
    assert packageCount pkgs.at-spi2-core codexComputerUse.dbus.packages == 1;
    assert packageCount pkgs.at-spi2-core codexComputerUse.systemd.user.packages == 1;
    assert codexComputerUse.programs.codexComputerUse.ydotoold.enable;
    assert
      codexComputerUse.programs.codexComputerUse.ydotoold.socket
      == "/home/module-test/.local/state/codex-computer-use/ydotool.sock";
    assert
      codexComputerUse.home.sessionVariables.YDOTOOL_SOCKET
      == codexComputerUse.programs.codexComputerUse.ydotoold.socket;
    assert
      codexComputerUse.systemd.user.sessionVariables.YDOTOOL_SOCKET
      == codexComputerUse.programs.codexComputerUse.ydotoold.socket;
    assert lib.hasInfix "ydotoold" ydotooldExecStart;
    assert lib.hasInfix "--socket-perm=0600" ydotooldExecStart;
    assert lib.hasInfix "unset NO_AT_BRIDGE" codexComputerUse.home.sessionVariablesExtra;
    assert !legacyCodexComputerUse.programs.codexComputerUse.ydotoold.enable;
    assert legacyCodexComputerUse.programs.codexComputerUse.ydotoold.socket == "/run/ydotoold/socket";
    assert !(builtins.hasAttr "ydotoold" legacyCodexComputerUse.systemd.user.services);
    assert lib.hasAttrByPath [ "programs" "codexOmx" "setupPlugin" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "codexDesktopLinux" "enable" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "codexComputerUse" "enable" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "codexComputerUseHyprland" "enable" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "nixslop" "codex" "enable" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "nixslop" "omx" "enable" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "nixslop" "desktop" "enable" ] aggregateEval.options;
    assert lib.hasAttrByPath [ "programs" "nixslop" "computerUse" "enable" ] aggregateEval.options;
    # The public alias composes the same modules. The plain desktop fixture
    # keeps the legacy ydotool keymap disabled unless it is explicitly
    # requested.
    assert aggregateProjection aggregateAlias == aggregateProjection aggregate;
    assert
      aggregateProjection aggregate == {
        codexDesktopEnabled = true;
        physicalLayout = "de";
        virtualDevices = [ ];
      };
    assert centralFacade.programs.codexOmx.enable;
    assert centralFacade.programs.codexDesktopLinux.enable;
    assert centralFacade.programs.codexDesktopLinux.computerUseUi.enable;
    assert centralFacade.programs.codexDesktopLinux.remoteMobileControl.enable;
    assert centralFacade.programs.codexComputerUse.enable;
    assert !centralFacade.programs.codexComputerUseHyprland.enable;
    assert
      centralFacade.programs.codexDesktopLinux.package.outPath
      == self.packages.${system}.codex-desktop-computer-use-ui.outPath;
    assert omxFacadeOnly.programs.codexOmx.enable;
    assert
      aggregate.programs.codexDesktopLinux.package.outPath
      == self.packages.${system}.codex-desktop.outPath;
    assert
      aggregate.programs.codexDesktopLinux.cliPackage.outPath == self.packages.${system}.codex.outPath;
    assert aggregate.wayland.windowManager.hyprland.settings.input.kb_layout == "de";
    assert
      lib.attrByPath [ "wayland" "windowManager" "hyprland" "settings" "device" ] [ ] aggregate == [ ];
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
