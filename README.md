# NixSlop

## Supported systems

- `x86_64-linux`
- `aarch64-linux`

## Included

- OpenCode: `opencode`
- Codex Desktop: `codex-desktop`
- Kimi Code: `kimi`
- Codex + OMX: `codex`, `omx`, `tmux`

## Use from Home Manager

```nix
inputs.nixslop.url = "github:cattosmile/NixSlop";
```

### OpenCode

```nix
{
  imports = [ inputs.nixslop.homeManagerModules.openCode ];

  programs.openCode.enable = true;
}
```

### Codex Desktop

```nix
{
  imports = [ inputs.nixslop.homeManagerModules.codexDesktop ];

  programs.codexDesktopLinux.enable = true;
}
```

### Kimi Code

```nix
{
  imports = [ inputs.nixslop.homeManagerModules.kimiCode ];

  programs.kimiCode.enable = true;
}
```

### Codex + OMX

```nix
{
  imports = [ inputs.nixslop.homeManagerModules.codexOmx ];

  programs.codexOmx.enable = true;
}
```

## Enable everything

```nix
{
  imports = [
    inputs.nixslop.homeManagerModules.openCode
    inputs.nixslop.homeManagerModules.codexDesktop
    inputs.nixslop.homeManagerModules.kimiCode
    inputs.nixslop.homeManagerModules.codexOmx
  ];

  programs.openCode.enable = true;
  programs.codexDesktopLinux.enable = true;
  programs.kimiCode.enable = true;
  programs.codexOmx.enable = true;
}
```

## Optional

```nix
programs.codexOmx.setupPlugin = false;
```

## Cachix (NixOS configuration)

```nix
nix.settings = {
  extra-substituters = [ "https://nixslop.cachix.org?priority=30" ];
  extra-trusted-public-keys = [
    "nixslop.cachix.org-1:Y41flUqIXb+Qx7D6hiugUE17RG4EkLaBn3UlVXc1oE8="
  ];
};
```

## Update

### Home Manager

```sh
nix flake update nixslop
home-manager switch
```

### NixOS

```sh
nix flake update nixslop
sudo nixos-rebuild switch --flake .#hostname
```
