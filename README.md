# NixSlop

NixSlop is my personal fast-moving app flake for programs I want newer than my
host's main `nixpkgs` pin.

The flake currently exposes packages, checks, and Home Manager modules for
`x86_64-linux` and `aarch64-linux`.

The intended interface is **Home Manager options only**. I do not want to
manage these apps by manually adding packages, overlays, or one-off install
snippets in my system config. Each app or app bundle should expose a small
option like:

```nix
programs.codexOmx.enable = true;
```

## Use from Home Manager

Add NixSlop as a flake input:

```nix
inputs.nixslop.url = "github:cattosmile/NixSlop";
```

Import the module you want and enable it with its Home Manager option:

```nix
{
  imports = [ inputs.nixslop.homeManagerModules.codexOmx ];

  programs.codexOmx.enable = true;
}
```

That option installs and wires the whole Codex + OMX bundle:

- Codex CLI from the newest `openai/codex` release successfully merged by the
  updater
- `oh-my-codex` / `omx` from the newest stable npm release successfully merged
  by the updater
- required runtime tools such as `tmux`
- Codex plugin registration for OMX, repaired during Home Manager activation
  when its configured source or cached command is missing or stale

## Updating installed apps

The GitHub workflow keeps this repository's package pins fresh. My host only
picks up newer app versions after updating its `nixslop` input and switching
Home Manager / NixOS:

```sh
nix flake update nixslop
home-manager switch
```

or the equivalent `nixos-rebuild switch --flake ...` flow if Home Manager is
managed by NixOS.

Codex CLI, Codex Desktop, Kimi Code, OpenCode, and OMX are built on the
`x86_64-linux` GitHub runner and published to the public `nixslop` Cachix
binary cache. NixOS hosts should configure that cache so a switch can download
matching signed Nix store paths instead of rebuilding the apps:

```nix
nix.settings = {
  extra-substituters = [ "https://nixslop.cachix.org?priority=30" ];
  extra-trusted-public-keys = [
    "nixslop.cachix.org-1:Y41flUqIXb+Qx7D6hiugUE17RG4EkLaBn3UlVXc1oE8="
  ];
};
```

The flake also advertises the same cache through `nixConfig` for commands that
accept flake-provided configuration. Declaring it in the host configuration is
preferred because it works non-interactively during Home Manager and NixOS
switches.

## Currently available modules

### `homeManagerModules.openCode`

Enable with:

```nix
imports = [ inputs.nixslop.homeManagerModules.openCode ];
programs.openCode.enable = true;
```

Purpose: install the pinned OpenCode CLI from its official flake as the
`opencode` command. The daily workflow tries to advance the upstream pin,
builds it, and publishes successful updates to the NixSlop binary cache.

### `homeManagerModules.codexDesktop`

Enable with:

```nix
imports = [ inputs.nixslop.homeManagerModules.codexDesktop ];
programs.codexDesktopLinux.enable = true;
```

Purpose: install the pinned upstream ChatGPT/Codex Desktop Linux package while
wiring its launcher directly to NixSlop's managed Codex CLI. The daily workflow
tries to advance the upstream flake and publishes successful builds to the
NixSlop binary cache.

### `homeManagerModules.kimiCode`

Enable with:

```nix
imports = [ inputs.nixslop.homeManagerModules.kimiCode ];
programs.kimiCode.enable = true;
```

Purpose: install the current packaged Kimi Code CLI release as the `kimi`
command without delegating installation or upgrades to an imperative installer.

### `homeManagerModules.codexOmx`

Enable with:

```nix
imports = [ inputs.nixslop.homeManagerModules.codexOmx ];
programs.codexOmx.enable = true;
```

Purpose: install Codex CLI and OMX as one managed bundle, then keep OMX plugin
setup in sync with the packaged Nix store path.

### Optional Home Manager overrides

The managed defaults should fit normal use. Advanced configurations can still
replace packages through `programs.openCode.package`,
`programs.kimiCode.package`, `programs.codexOmx.codexPackage`, and
`programs.codexOmx.ohMyCodexPackage`.

The Codex + OMX module normally runs idempotent user-scope plugin setup against
`~/.codex` during activation. Set `programs.codexOmx.setupPlugin = false;` only
when plugin registration is managed elsewhere.

## Automation

`.github/workflows/update-packages.yml` runs once per day at 03:17 UTC and can
also be started manually. It currently:

1. checks releases for Codex CLI, Kimi Code, and OMX, while advancing the pinned
   Codex Desktop and OpenCode flakes,
2. refreshes package hashes when newer versions exist,
3. refreshes the vendored OMX `Cargo.lock` used for reproducible Rust helper builds,
4. validates flake evaluation across supported systems,
5. builds and smoke-tests Codex CLI, Codex Desktop, Kimi Code, OpenCode, and OMX,
6. publishes their signed runtime closures to `nixslop.cachix.org`, and
7. commits only expected pin files to an update branch, creates or updates a PR,
   and tries to enable auto-merge.

Updater network requests have bounded retries, updater commands have a timeout,
and multi-file pin updates roll back if hash calculation fails. The workflow
also rejects changes outside `flake.lock`, package hash files, and the OMX
`Cargo.lock`.

`.github/workflows/check.yml` is the read-only safety net for normal changes.
Every pull request and push to `main`, plus manual runs, executes the updater
unit tests, evaluates both supported systems, runs lightweight Home Manager
module contract assertions, then builds and smoke-tests all five apps on
`x86_64-linux`. The module assertions check generated configuration; they do
not perform a real Home Manager activation.

## Check locally

Enter the development shell, then run the fast checks used by CI:

```sh
nix develop
python3 -m unittest discover -s tests -v
nix flake check --all-systems --no-build --print-build-logs
```

For the full package check, build the five outputs and run their version or
executable smoke tests as defined in `.github/workflows/check.yml`.

Future apps should follow the same pattern: pin an upstream release or revision,
expose a focused Home Manager module option, document that option-based
interface here, and let automation refresh the pin.
