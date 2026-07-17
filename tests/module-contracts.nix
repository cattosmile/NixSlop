{
  self,
  pkgs,
}:

let
  lib = pkgs.lib.extend (
    _final: _previous: {
      hm.dag.entryAfter = after: text: { inherit after text; };
    }
  );

  system = pkgs.stdenv.hostPlatform.system;
  packagePaths = packages: builtins.map (package: package.outPath) packages;

  openCode = self.homeManagerModules.openCode {
    config.programs.openCode = {
      enable = true;
      package = self.packages.${system}.opencode;
    };
    inherit lib pkgs;
  };

  kimiCode = self.homeManagerModules.kimiCode {
    config.programs.kimiCode = {
      enable = true;
      package = self.packages.${system}.kimi-code;
    };
    inherit lib pkgs;
  };

  codexDesktop = self.homeManagerModules.codexDesktop {
    inherit lib pkgs;
  };

  codexOmx = self.homeManagerModules.codexOmx {
    config = {
      home.homeDirectory = "/home/module-test";
      programs.codexOmx = {
        enable = true;
        codexPackage = self.packages.${system}.codex;
        ohMyCodexPackage = self.packages.${system}.oh-my-codex;
        setupPlugin = true;
      };
    };
    inherit lib pkgs;
  };

  openCodeConfig = openCode.config.content;
  kimiCodeConfig = kimiCode.config.content;
  codexOmxConfig = codexOmx.config.content;
  codexOmxActivation = codexOmxConfig.home.activation.refreshOhMyCodexPlugin.content;
in
assert openCode.config.condition;
assert builtins.hasAttr "enable" openCode.options.programs.openCode;
assert packagePaths openCodeConfig.home.packages == [ self.packages.${system}.opencode.outPath ];
assert kimiCode.config.condition;
assert builtins.hasAttr "package" kimiCode.options.programs.kimiCode;
assert packagePaths kimiCodeConfig.home.packages == [ self.packages.${system}.kimi-code.outPath ];
assert builtins.length codexDesktop.imports == 1;
assert
  codexDesktop.programs.codexDesktopLinux.cliPackage.content.outPath
  == self.packages.${system}.codex.outPath;
assert codexOmx.config.condition;
assert
  packagePaths codexOmxConfig.home.packages == packagePaths [
    self.packages.${system}.codex
    self.packages.${system}.oh-my-codex
    pkgs.tmux
  ];
assert codexOmxConfig.home.activation.refreshOhMyCodexPlugin.condition;
assert codexOmxActivation.after == [ "writeBoundary" ];
assert lib.hasInfix "--unset=OMX_ROOT" codexOmxActivation.text;
assert lib.hasInfix ''CODEX_HOME="/home/module-test/.codex"'' codexOmxActivation.text;
assert lib.hasInfix "omx setup --plugin --force --scope user" codexOmxActivation.text;
true
