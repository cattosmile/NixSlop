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
  codex = self.packages.${system}.codex;
  chatgptDesktop = self.packages.${system}.chatgpt-desktop;
  chatgptDesktopComputerUse = self.packages.${system}.codex-desktop-computer-use-ui;

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

  codex-code-mode-host = pkgs.runCommand "nixslop-codex-code-mode-host" { } ''
    test -x ${codex}/bin/codex
    test -x ${codex}/bin/codex-code-mode-host
    test "$(${codex}/bin/codex --version)" = "codex-cli ${codex.version}"
    touch "$out"
  '';

  home-manager-contracts =
    assert homeManagerContracts.assertions;
    homeManagerContracts.generatedFiles;

  formatting = pkgs.runCommand "nixslop-formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
    find ${../.} -type f -name '*.nix' -print0 | xargs -0 nixfmt --check
    touch "$out"
  '';

  chatgpt-desktop-contract = pkgs.runCommand "nixslop-chatgpt-desktop-contract" { } ''
    test -x ${chatgptDesktop}/bin/chatgpt
    test -x ${chatgptDesktop}/bin/codex-desktop
    test -f ${chatgptDesktop}/share/applications/chatgpt.desktop
    grep -Fq 'Exec=${chatgptDesktop}/bin/chatgpt %U' ${chatgptDesktop}/share/applications/chatgpt.desktop
    test -x ${chatgptDesktop.fhsenv}/usr/lib64/chatgpt/ChatGPT
    test -x ${chatgptDesktop}/usr/lib/chatgpt/ChatGPT
    test -x ${chatgptDesktop}/usr/lib/chatgpt/resources/cua_node/lib/node_modules/@oai/sky/bin/linux/sky_linux_x64
    touch "$out"
  '';

  chatgpt-desktop-computer-use-contract =
    pkgs.runCommand "nixslop-chatgpt-desktop-computer-use-contract"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        plugin=${chatgptDesktopComputerUse}/opt/codex-desktop/resources/plugins/openai-bundled/plugins/computer-use
        marketplace=${chatgptDesktopComputerUse}/opt/codex-desktop/resources/plugins/openai-bundled/.agents/plugins/marketplace.json
        patchReport=${chatgptDesktopComputerUse}/opt/codex-desktop/.codex-linux/patch-report.json
        test -x ${chatgptDesktopComputerUse}/bin/chatgpt
        test -x ${chatgptDesktopComputerUse}/bin/codex-desktop
        test -x "$plugin/bin/codex-computer-use-linux"
        test -x "$plugin/bin/codex-computer-use-cosmic"
        test -x "$plugin/bin/codex-chrome-extension-host"
        test -f "$plugin/.codex-plugin/plugin.json"
        test -f "$plugin/.mcp.json"
        test -f "$plugin/assets/app-icon.png"
        jq -e '.plugins | any(.name == "computer-use" and .source.path == "./plugins/computer-use")' "$marketplace" >/dev/null
        jq -e '.enabledFeatures | index("computer-use-linux") != null' "$patchReport" >/dev/null
        jq -e '
          [.patches[] | select(.name == "feature:computer-use-linux:ui-availability" or .name == "feature:computer-use-linux:host-platform" or .name == "feature:computer-use-linux:install-flow") | .status]
          | length == 3 and all(. == "applied" or . == "already-applied")
        ' "$patchReport" >/dev/null
        source=${chatgptDesktopComputerUse.computerUseBinaries.computerUseSource}
        grep -Fq 'BackendKind::Hyprland,' "$source/computer-use-linux/src/windowing/registry.rs"
        grep -Fq 'HYPRLAND_BACKEND => hyprland::move_window' "$source/computer-use-linux/src/windowing/registry.rs"
        grep -Fq 'capture_with_grim' "$source/computer-use-linux/src/screenshot.rs"
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
