# NixSlop

Personal fast-moving Nix flake for apps that should track upstream releases faster than your host's main nixpkgs pin.

Currently packaged:

- `codex` / `codex-latest` - OpenAI Codex CLI from `openai/codex` GitHub releases.
- `oh-my-codex` / `omx` / `omx-latest` - oh-my-codex workflow layer with Nix-built native helper binaries.

## Use directly

```sh
nix run github:cattosmile/NixSlop#codex -- --version
nix run github:cattosmile/NixSlop#omx -- version
```

## Use from a NixOS flake

Add the input:

```nix
inputs.nixslop.url = "github:cattosmile/NixSlop";
```

Then install the package:

```nix
{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    inputs.nixslop.packages.${pkgs.system}.codex
    inputs.nixslop.packages.${pkgs.system}.oh-my-codex
  ];
}
```

Or use the overlay:

```nix
{
  nixpkgs.overlays = [ inputs.nixslop.overlays.default ];
  environment.systemPackages = [
    pkgs.codex-latest
    pkgs.omx-latest
  ];
}
```

## Use with Home Manager

For Codex plus oh-my-codex plugin setup, import the module:

```nix
{
  imports = [ inputs.nixslop.homeManagerModules.codexOmx ];

  programs.codexOmx.enable = true;
}
```

The module installs Codex, OMX, and tmux, then refreshes the local Codex plugin registration when the Nix store OMX package changes.

On the host, update with:

```sh
nix flake lock --update-input nixslop
# or: nix flake update nixslop
```

## Automation

`.github/workflows/update-codex.yml` runs hourly. It:

1. queries the latest `openai/codex` GitHub release and latest stable `oh-my-codex` npm version,
2. rewrites package hash files when newer stable versions exist,
3. recalculates Nix source/Cargo/npm/runtime binary hashes,
4. validates flake evaluation and builds the OMX package smoke target, and
5. commits the changed pins back to the repository.

This keeps the repo moving independently from your host flake. Your host only picks up newer Codex/OMX packages after you update its `nixslop` input lock.
