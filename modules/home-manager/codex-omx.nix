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
  hasDesktopComputerUseOption = lib.hasAttrByPath [
    "programs"
    "codexDesktopLinux"
    "computerUseUi"
    "enable"
  ] options;
  desktopComputerUseEnabled =
    hasDesktopComputerUseOption
    && lib.attrByPath [
      "programs"
      "codexDesktopLinux"
      "computerUseUi"
      "enable"
    ] false config;
  computerUsePlugins = lib.optional desktopComputerUseEnabled "computer-use@openai-bundled";
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

    restoreDefaultPlugins = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Restore Codex's default document, spreadsheet, presentation, PDF,
        template, Teams, and Outlook Calendar plugins when they are available.
        The activation only adds missing plugin entries and never touches Codex
        authentication, account data, skills, or existing plugin entries. It is
        skipped when native `programs.codex` owns the generated config file.
      '';
    };

    primaryRuntimePath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cache/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime";
      defaultText = lib.literalExpression ''
        "${config.home.homeDirectory}/.cache/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime"
      '';
      description = ''
        Local Codex primary-runtime marketplace path. Codex Desktop populates
        this path; if it is not present, the activation leaves it untouched.
      '';
    };

    defaultPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "documents@openai-primary-runtime"
        "spreadsheets@openai-primary-runtime"
        "presentations@openai-primary-runtime"
        "pdf@openai-primary-runtime"
        "template-creator@openai-primary-runtime"
        "outlook-calendar@openai-curated"
        "teams@openai-curated"
      ];
      description = "Codex plugin IDs restored by the default-plugin activation.";
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

      home.activation.restoreCodexDefaultPlugins =
        lib.mkIf (cfg.restoreDefaultPlugins && (!nativeCodexEnabled || cfg.setupPlugin))
          (
            lib.hm.dag.entryAfter ([ "writeBoundary" ] ++ lib.optional cfg.setupPlugin "refreshOhMyCodexPlugin")
              ''
                codex_bin="${effectiveCodexPackage}/bin/codex"
                codex_home="${config.home.homeDirectory}/.codex"
                codex_config="$codex_home/config.toml"
                primary_runtime="${cfg.primaryRuntimePath}"

                # The primary runtime is downloaded by Codex Desktop and is not part
                # of NixSlop. Do not create or replace it when it is unavailable.
                if [ -f "$primary_runtime/.agents/plugins/marketplace.json" ] \
                  && ! grep -Fq '[marketplaces.openai-primary-runtime]' "$codex_config" 2>/dev/null; then
                  if ! CODEX_HOME="$codex_home" "$codex_bin" plugin marketplace add "$primary_runtime" >/dev/null 2>&1; then
                    echo "NixSlop: could not register Codex primary-runtime marketplace; keeping existing config" >&2
                  fi
                fi

                for plugin in ${
                  lib.concatMapStringsSep " " lib.escapeShellArg (
                    lib.unique (cfg.defaultPlugins ++ computerUsePlugins)
                  )
                }; do
                  # Never change a user's explicit enablement or source choice. The
                  # Codex CLI is called only for plugin IDs absent from config.toml.
                  if [ -f "$codex_config" ] && grep -Fq "[plugins.\"$plugin\"]" "$codex_config"; then
                    continue
                  fi
                  if ! CODEX_HOME="$codex_home" "$codex_bin" plugin add "$plugin" --json >/dev/null 2>&1; then
                    # A reserved marketplace (for example openai-curated) may not be
                    # materialized until Codex Desktop has completed its sync. This
                    # is intentionally non-fatal so rebuilds remain usable offline.
                    echo "NixSlop: Codex default plugin $plugin is not available yet; leaving existing config" >&2
                  fi
                  done
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
