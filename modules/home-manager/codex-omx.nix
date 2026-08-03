{ self }:

{
  config,
  lib,
  options,
  pkgs,
  ...
}:

let
  cfg = config.programs.codexOmx;
  system = pkgs.stdenv.hostPlatform.system;
  hasNativeCodexSupport =
    lib.hasAttrByPath [
      "programs"
      "codex"
      "enable"
    ] options
    && lib.hasAttrByPath [
      "programs"
      "codex"
      "package"
    ] options;
  configuredCodexPackage = cfg.codexPackage;
  nativeCodexEnabled =
    hasNativeCodexSupport
    && lib.attrByPath [
      "programs"
      "codex"
      "enable"
    ] false config;
  nativeCodexPackage =
    if hasNativeCodexSupport then
      lib.attrByPath [
        "programs"
        "codex"
        "package"
      ] null config
    else
      null;
  nativeCodexProvidesPackage = nativeCodexEnabled && nativeCodexPackage != null;
  effectiveCodexPackage =
    if nativeCodexProvidesPackage then nativeCodexPackage else configuredCodexPackage;
  omxPackage = cfg.ohMyCodexPackage;
  omxPluginRoot = "${omxPackage}/lib/node_modules/oh-my-codex";
  omxPlugin =
    pkgs.runCommand "oh-my-codex-plugin"
      {
        pname = "oh-my-codex";
        version = omxPackage.version or "0.0.0";
      }
      ''
        ln -s ${omxPluginRoot} "$out"
      '';
  hasDeclarativePluginSupport = lib.hasAttrByPath [
    "programs"
    "codex"
    "plugins"
  ] options;
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
      default = self.packages.${system}.oh-my-codex.override { codex = effectiveCodexPackage; };
      defaultText = lib.literalExpression ''
        inputs.nixslop.packages.${pkgs.stdenv.hostPlatform.system}.oh-my-codex.override {
          codex =
            if config.programs.codex.enable && config.programs.codex.package != null then
              config.programs.codex.package
            else
              config.programs.codexOmx.codexPackage;
        }
      '';
      description = "oh-my-codex package to install and register as a Codex plugin, bound to the effective Codex package.";
    };

    setupPlugin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run idempotent oh-my-codex plugin setup during Home Manager activation.";
    };
  };

  config = lib.mkMerge [
    (lib.optionalAttrs hasNativeCodexSupport {
      # The native module owns declarative Codex settings when it is enabled.
      # Consumers still receive NixSlop's Codex build unless they override it.
      programs.codex.package = lib.mkDefault configuredCodexPackage;
    })
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !cfg.setupPlugin || !nativeCodexEnabled;
          message = ''
            `programs.codexOmx.setupPlugin = true` requires
            `programs.codex.enable = false` so `omx setup` can keep
            ~/.codex/config.toml mutable. Set `setupPlugin = false` to use the
            native Home Manager Codex settings and dotfile options.
          '';
        }
        {
          assertion = cfg.setupPlugin || !nativeCodexEnabled || hasDeclarativePluginSupport;
          message = ''
            `programs.codexOmx.setupPlugin = false` with
            `programs.codex.enable = true` requires a Home Manager version
            that provides `programs.codex.plugins`. Upgrade Home Manager or
            keep `setupPlugin = true` with native Codex disabled.
          '';
        }
      ];

      home.packages = lib.optional (!nativeCodexProvidesPackage) effectiveCodexPackage ++ [
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
    })
    (lib.optionalAttrs hasDeclarativePluginSupport (
      lib.mkIf (cfg.enable && !cfg.setupPlugin && nativeCodexEnabled) {
        # Pass a derivation root so Home Manager uses its non-IFD plugin path.
        # A raw string here makes `builtins.pathExists` realize foreign-system
        # OMX packages during cross-system flake evaluation.
        programs.codex.plugins = lib.mkAfter [ omxPlugin ];
      }
    ))
  ];
}
