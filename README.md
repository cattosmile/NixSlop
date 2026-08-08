# NixSlop

## Flake input

Add NixSlop to the `inputs` of your system flake:

```nix
{
  inputs = {
    nixslop.url = "github:cattosmile/NixSlop";
  };
}
```

## Home Manager

Then add this module to the user's Home Manager configuration:

```nix
{ inputs, ... }:

{
  imports = [ inputs.nixslop.homeManagerModules.default ];

  programs.codexDesktopLinux = {
    enable = true;
    computerUseUi.enable = true;
    remoteMobileControl.enable = true;
  };

  programs.codexOmx.enable = true;
}
```

This installs Codex Desktop, the Computer Use UI, Remote Mobile Control,
Codex CLI, oh-my-codex, and tmux. Do not enable Home Manager's native
`programs.codex` module together with this setup.

## NixOS Computer Use

Enable the system dependencies separately in the NixOS configuration:

```nix
{ inputs, ... }:

{
  imports = [ inputs.nixslop.nixosModules.codexComputerUse ];

  services.codexComputerUse = {
    enable = true;
    user = "user";
  };
}
```

This enables AT-SPI2 and `ydotool`, and adds `user` to the `ydotool` group.

## Cachix

Add the NixSlop binary cache to your NixOS configuration:

```nix
{
  nix.settings = {
    extra-substituters = [
      "https://nixslop.cachix.org?priority=30"
    ];
    extra-trusted-public-keys = [
      "nixslop.cachix.org-1:Y41flUqIXb+Qx7D6hiugUE17RG4EkLaBn3UlVXc1oE8="
    ];
  };
}
```

## Activate

```bash
sudo nixos-rebuild switch --flake .#hostname
```
