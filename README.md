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

## Currently available modules

### `homeManagerModules.codexOmx`

Enable with:

```nix
programs.codexOmx.enable = true;
```

Purpose: install Codex CLI and OMX as one managed bundle, then keep OMX plugin setup in sync with the packaged Nix store path.

## Automation

`.github/workflows/update-codex.yml` runs on a schedule. It currently:

1. checks the latest stable Codex release and latest stable OMX npm version,
2. refreshes package hashes when newer versions exist,
3. refreshes the vendored OMX `Cargo.lock` used for reproducible Rust helper builds,
4. validates flake evaluation across supported systems,
5. builds the OMX package smoke target, and
6. commits changed pins back to the repository.

Future apps should follow the same pattern: package the latest upstream release in NixSlop, expose a focused Home Manager module option, document only that option-based interface here, and let automation refresh pins.
