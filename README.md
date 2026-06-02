# NixSlop

Personal fast-moving Nix flake for apps that should track upstream releases faster than your host's main nixpkgs pin.

Currently packaged:

- `codex` / `codex-latest` - OpenAI Codex CLI from `openai/codex` GitHub releases.

## Use directly

```sh
nix run github:cattosmile/NixSlop#codex -- --version
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
  ];
}
```

Or use the overlay:

```nix
{
  nixpkgs.overlays = [ inputs.nixslop.overlays.default ];
  environment.systemPackages = [ pkgs.codex-latest ];
}
```

On the host, update with:

```sh
nix flake lock --update-input nixslop
# or: nix flake update nixslop
```

## Automation

`.github/workflows/update-codex.yml` runs hourly. It:

1. queries the latest `openai/codex` GitHub release,
2. rewrites `packages/codex/hashes.json` if a newer stable `rust-v<version>` release exists,
3. recalculates Nix source/Cargo/runtime binary hashes,
4. validates flake evaluation, and
5. commits the changed pins back to the repository.

This keeps the repo moving independently from your host flake. Your host only picks up a newer Codex after you update its `nixslop` input lock.
