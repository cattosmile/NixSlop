{
  self,
  pkgs,
  home-manager,
}:

let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  outputContracts = import ../tests/output-contracts.nix { inherit self pkgs; };
  moduleContracts = import ../tests/module-contracts.nix { inherit self pkgs; };
  homeManagerContracts = import ../tests/home-manager-contracts.nix {
    inherit self pkgs home-manager;
  };
  codexDesktop = self.packages.${system}.codex-desktop;

  assertionCheck =
    name: condition:
    assert condition;
    pkgs.runCommand "nixslop-${name}" { } ''
      touch "$out"
    '';
in
{
  output-contracts = assertionCheck "output-contracts" outputContracts;
  module-contracts = assertionCheck "module-contracts" moduleContracts;

  home-manager-contracts =
    assert homeManagerContracts.assertions;
    homeManagerContracts.generatedFiles;

  formatting = pkgs.runCommand "nixslop-formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
    find ${../.} -type f -name '*.nix' -print0 | xargs -0 nixfmt --check
    touch "$out"
  '';

  codex-desktop-patch-source = codexDesktop.computerUseSource;

  codex-desktop-computer-use = pkgs.runCommand "nixslop-codex-desktop-computer-use" { } ''
    plugin="${codexDesktop}/opt/codex-desktop/resources/plugins/openai-bundled/plugins/computer-use"
    test -f "$plugin/.codex-plugin/plugin.json"
    test -x "$plugin/bin/codex-computer-use-linux"
    grep -Fq 'grim' "$plugin/bin/codex-computer-use-linux"
    test -x "$plugin/bin/codex-computer-use-cosmic"
    test -x "$plugin/bin/codex-chrome-extension-host"
    grep -Fq '"hyprland"' "$plugin/.codex-plugin/plugin.json"
    grep -Fq '"grim"' "$plugin/.codex-plugin/plugin.json"
    grep -Fq '"ydotool"' "$plugin/.codex-plugin/plugin.json"
    if grep -Fq '"gnome"' "$plugin/.codex-plugin/plugin.json"; then
      echo "unexpected GNOME keyword in the packaged Computer Use plugin" >&2
      exit 1
    fi
    touch "$out"
  '';
}
// lib.optionalAttrs (builtins.pathExists ../.github/workflows) {
  actionlint =
    pkgs.runCommand "nixslop-actionlint"
      {
        nativeBuildInputs = [ pkgs.actionlint ];
      }
      ''
        cd ${../.}
        actionlint \
          -config-file .github/actionlint.yaml \
          .github/workflows/*.yml
        touch "$out"
      '';
}
// lib.optionalAttrs (builtins.pathExists ../tests/test_workflow_contracts.py) {
  workflow-contracts =
    pkgs.runCommand "nixslop-workflow-contracts"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        export PYTHONDONTWRITEBYTECODE=1
        cd ${../.}
        python3 -m unittest discover -s tests -p 'test_workflow_contracts.py' -v
        touch "$out"
      '';
}
