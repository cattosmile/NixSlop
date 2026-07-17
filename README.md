# NixSlop

NixSlop is my personal fast-moving app flake for programs I want newer than my host's main `nixpkgs` pin.

The intended interface is **Home Manager options only**. I do not want to manage these apps by manually adding packages, overlays, or one-off install snippets in my system config. Each app or app bundle should expose a small option like:

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

- latest packaged Codex CLI from `openai/codex` releases
- latest packaged `oh-my-codex` / `omx` from stable npm releases
- required runtime tools such as `tmux`
- Codex plugin registration for OMX, refreshed when the Nix store OMX package changes

## Updating installed apps

The GitHub workflow keeps this repository's package pins fresh. My host only picks up newer app versions after updating its `nixslop` input and switching Home Manager / NixOS:

```sh
nix flake update nixslop
home-manager switch
```

or the equivalent `nixos-rebuild switch --flake ...` flow if Home Manager is managed by NixOS.

Codex CLI, Codex Desktop, Kimi Code, and OMX are built by the update workflow and published to the public
`nixslop` Cachix binary cache. NixOS hosts should configure that cache so a
switch downloads the signed Nix store paths instead of rebuilding the apps:

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

### `homeManagerModules.codexDesktop`

Enable with:

```nix
imports = [ inputs.nixslop.homeManagerModules.codexDesktop ];
programs.codexDesktopLinux.enable = true;
```

Purpose: install the upstream ChatGPT/Codex Desktop Linux package while wiring
its launcher directly to NixSlop's managed Codex CLI. The daily workflow updates
the pinned upstream flake and publishes the built desktop app to the NixSlop
binary cache.

### `homeManagerModules.kimiCode`

Enable with:

```nix
programs.kimiCode.enable = true;
```

Purpose: install the latest packaged Kimi Code CLI release as the `kimi`
command without delegating installation or upgrades to an imperative installer.

### `homeManagerModules.codexOmx`

Enable with:

```nix
programs.codexOmx.enable = true;
```

Purpose: install Codex CLI and OMX as one managed bundle, then keep OMX plugin setup in sync with the packaged Nix store path.

## Automation

`.github/workflows/update-packages.yml` runs once per day at 03:17 UTC. It currently:

1. checks the latest stable Codex CLI, Codex Desktop, Kimi Code, and OMX releases,
2. refreshes package hashes when newer versions exist,
3. refreshes the vendored OMX `Cargo.lock` used for reproducible Rust helper builds,
4. validates flake evaluation across supported systems,
5. builds and smoke-tests Codex CLI, Codex Desktop, Kimi Code, and OMX,
6. publishes their signed runtime closures to `nixslop.cachix.org`, and
7. commits changed pins to an update branch and maintains an auto-merge PR.

Future apps should follow the same pattern: package the latest upstream release in NixSlop, expose a focused Home Manager module option, document only that option-based interface here, and let automation refresh pins.
