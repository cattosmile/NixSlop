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

Then add the aggregate module to the user's Home Manager configuration:

```nix
{ inputs, ... }:

{
  imports = [ inputs.nixslop.homeManagerModules.default ];

  programs.nixslop = {
    codex.enable = true;
    desktop.enable = true;
  };
}
```

This installs the official OpenAI ChatGPT Desktop app for Linux, its Codex
integration, the NixSlop Codex CLI, oh-my-codex, and tmux. The app is launched
as `chatgpt`; the historical `codex-desktop` launcher name remains available
as a compatibility alias. The official app includes its own Linux Computer Use
backend, so the normal setup does not need `ydotoold` or
`services.codexComputerUse`.

`programs.nixslop.omx.enable = true` is an equivalent selector for the current
combined Codex/oh-my-codex integration; normally use one of `codex.enable` or
`omx.enable`. Do not enable Home Manager's native `programs.codex` module
together with this setup unless you intentionally want its declarative mode.

The compatibility flags
`programs.nixslop.desktop.computerUseUi.enable` and
`programs.nixslop.desktop.remoteMobileControl.enable` are retained for existing
configurations. Feature availability for the official app is controlled by the
app itself; these flags no longer select patched Nix package variants.

The official Debian package is unpacked and run inside a Nix FHS environment.
It is pinned by version and hash in `packages/chatgpt-desktop/source.nix`, so
Nix never runs Debian maintainer scripts or modifies `/etc/apt`. The updater
workflow reads OpenAI's package index and refreshes only that source pin.

The historical module paths remain available for advanced configuration:
`programs.codexDesktopLinux`, `programs.codexComputerUse`,
`programs.codexOmx`, and `programs.codexComputerUseHyprland`.

## NixOS integration

The normal official-app setup does not import a NixSlop NixOS module and does
not define `services.codexComputerUse`. If the desktop session needs AT-SPI2
for another application, enable it independently:

```nix
{
  services.gnome.at-spi2-core.enable = true;
}
```

The legacy Home Manager `ydotoold` service remains available for users who
explicitly need the old NixSlop Computer Use backend. Enable it with
`programs.nixslop.computerUse.enable = true`; on Hyprland, also enable
`programs.nixslop.desktop.hyprland.enable = true`. This is not required by the
official ChatGPT Desktop app.

That legacy service runs as the desktop user, who needs read/write access to
`/dev/uinput`. Device permissions are system-level and cannot be managed by
Home Manager. Add the user to the system's `uinput` group if the distribution
does not already provide a suitable `uaccess` rule.

If the user service cannot access `/dev/uinput`, the optional NixOS fallback is:

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

The official Linux app is currently distributed by OpenAI as a preview for
Ubuntu/Debian/Fedora. NixSlop packages the official `.deb` for NixOS on
x86_64-linux and aarch64-linux; the `.rpm` is not needed on NixOS. See the
[official Linux app documentation](https://learn.chatgpt.com/docs/linux/linux-app)
for OpenAI's supported distributions and installation details.

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
