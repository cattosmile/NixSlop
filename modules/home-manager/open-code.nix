{ self }:

{
  config,
  lib,
  options,
  pkgs,
  ...
}:

let
  cfg = config.programs.openCode;
  system = pkgs.stdenv.hostPlatform.system;
  defaultPackage = self.packages.${system}.opencode;
  hasNativeOpenCode = lib.hasAttrByPath [
    "programs"
    "opencode"
    "enable"
  ] options;
in
{
  options.programs.openCode = {
    enable = lib.mkEnableOption "OpenCode CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "inputs.nixslop.packages.${pkgs.stdenv.hostPlatform.system}.opencode";
      description = "OpenCode CLI package to install.";
    };
  };

  config = lib.mkMerge [
    (lib.optionalAttrs hasNativeOpenCode {
      # Keep the historical camel-case options as a compatibility adapter. The
      # native Home Manager module remains the sole owner of package installation
      # and OpenCode's generated files.
      programs.opencode.package = lib.mkDefault cfg.package;
    })
    (lib.mkIf cfg.enable (
      if hasNativeOpenCode then
        { programs.opencode.enable = true; }
      else
        {
          # Home Manager versions predating the native OpenCode module retain
          # the original NixSlop installation behavior.
          home.packages = [ cfg.package ];
        }
    ))
  ];
}
