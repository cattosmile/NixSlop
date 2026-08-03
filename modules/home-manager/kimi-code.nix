{ self }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.kimiCode;
  system = pkgs.stdenv.hostPlatform.system;
  tomlFormat = pkgs.formats.toml { };
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

    settings = lib.mkOption {
      inherit (tomlFormat) type;
      default = { };
      description = "Kimi Code settings written to ~/.kimi-code/config.toml.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.file.".kimi-code/config.toml" = lib.mkIf (cfg.settings != { }) {
      source = tomlFormat.generate "kimi-code-config.toml" cfg.settings;
    };
  };
}
