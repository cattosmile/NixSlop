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

  programs.codexComputerUse.enable = true;
  programs.codexOmx.enable = true;
}
```

This installs Codex Desktop, the Computer Use UI, the Linux Computer Use
runtime, Remote Mobile Control, Codex CLI, oh-my-codex, and tmux. The Computer
Use runtime is managed by Home Manager: it installs AT-SPI2 and ydotool,
registers the AT-SPI D-Bus services, and starts a per-user `ydotoold` service
with a private socket. Do not enable Home Manager's native `programs.codex`
module together with this setup.

## NixOS integration

The normal setup does not import the NixSlop NixOS module or define
`services.codexComputerUse`. If your NixOS desktop configuration does not
already enable AT-SPI2, keep only this built-in system option:

```nix
{
  services.gnome.at-spi2-core.enable = true;
}
```

NixOS sets `NO_AT_BRIDGE=1` and `GTK_A11Y=none` when its AT-SPI2 option is
disabled. The Home Manager module removes those values from shell sessions,
but enabling AT-SPI2 at the system level is the most reliable choice for
desktop applications launched directly by the graphical session.

The Home Manager `ydotoold` service runs as the desktop user, so that user must
have read/write access to `/dev/uinput`. Device permissions are system-level
and cannot be managed by Home Manager. For example, add the user to the
system's `uinput` group if your distribution does not already provide a
`uaccess` rule.

If the user service cannot access `/dev/uinput`, the existing NixOS module is
available as a fallback:

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

When Home Manager is integrated into NixOS, enabling this fallback is detected
automatically and Home Manager reuses `/run/ydotoold/socket` instead of
starting a second daemon. For standalone Home Manager, set
`programs.codexComputerUse.ydotoold.enable = false` and
`programs.codexComputerUse.ydotoold.socket = "/run/ydotoold/socket"` when using
the system daemon.

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
