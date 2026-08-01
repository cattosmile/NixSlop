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

The default package includes the Hyprland-compatible Computer Use plugin and
its native Linux backend. The system-side accessibility and input services
can be enabled through the companion NixOS module:

### NixOS Computer Use runtime

```nix
{
  imports = [ inputs.nixslop.nixosModules.codexComputerUse ];

  services.codexComputerUse = {
    enable = true;
    user = "user";
  };
}
```

This enables AT-SPI2 and ydotool without enabling GNOME Shell or requiring a
GNOME session. Set `user = null` when ydotool group membership is managed
elsewhere.

### Hyprland ydotool keyboard mapping

`ydotool type` emits US physical keycodes. On Hyprland, keep the virtual
ydotool keyboard on an isolated US keymap while leaving physical keyboards on
their normal layout:

```nix
wayland.windowManager.hyprland.settings.config.device = {
  "ydotoold-virtual-device" = {
    kb_layout = "us";
    kb_variant = "";
    kb_options = "";
  };
};
```

The packaged Computer Use backend uses the same US-mapped virtual device, so
manual `ydotool type` commands and Computer Use produce the same characters.

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
