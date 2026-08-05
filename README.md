# NixSlop

NixSlop provides fast-moving developer tools through Home Manager while keeping
their package pins, desktop integration, checks, and daily updates in one flake.
Import one aggregate module, enable only the programs you want, and keep the
rest of your system configuration in the consuming flake.

Supported systems:

- `x86_64-linux`
- `aarch64-linux`

## Use the aggregate Home Manager module

Add the input:

```nix
inputs.nixslop = {
  url = "github:cattosmile/NixSlop";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Import `homeManagerModules.default` (or its identical `nixslop` alias), then
use the native Home Manager `programs.opencode` and `programs.codex` settings
alongside the NixSlop-specific Kimi, desktop, and OMX options:

```nix
{
  imports = [ inputs.nixslop.homeManagerModules.default ];

  programs = {
    opencode = {
      enable = true;
      settings = {
        model = "provider/model";
        autoupdate = false;
      };
      context = ''
        Project instructions for OpenCode.
      '';
    };

    kimiCode = {
      enable = true;
      settings = {
        default_model = "kimi-code/k3";
        telemetry = false;
      };
    };

    codexOmx = {
      enable = true;
      setupPlugin = false;
    };

    codex = {
      enable = true;
      settings = {
        model = "gpt-5.6";
        approval_policy = "never";
      };
      context = ''
        Shared Codex instructions.
      '';
    };

    codexDesktopLinux.enable = true;

    ccSwitch.enable = true;
  };
}
```

The aggregate module imports all Home Manager integrations in NixSlop; it does
not enable programs by itself. NixSlop supplies its package builds as defaults,
so normal Home Manager settings still own generated OpenCode and Codex files.

### Choose one Codex configuration owner

`programs.codexOmx.setupPlugin` decides who owns `~/.codex/config.toml`:

- `setupPlugin = false` allows the native Home Manager
  `programs.codex.settings`, `programs.codex.context`, and related options to
  own Codex configuration declaratively. This is the recommended mode for a
  Nix-managed configuration. It requires a Home Manager revision that provides
  `programs.codex.plugins`; the module fails with a targeted assertion on older
  revisions instead of silently omitting OMX.
- `setupPlugin = true` (the compatibility default) runs idempotent
  `omx setup --plugin` during Home Manager activation. OMX then owns the
  mutable Codex configuration, so `programs.codex.enable` must remain `false`.

The module rejects enabling mutable OMX setup and declarative Codex file
generation at the same time. A mutable OMX setup is therefore explicit:

```nix
programs = {
  codex.enable = false;
  codexOmx = {
    enable = true;
    setupPlugin = true;
  };
};
```

### Kimi settings and secrets

`programs.kimiCode.settings` generates `~/.kimi-code/config.toml`. Values
declared in Home Manager are copied through the Nix store. Do not put API keys
or other secrets in this attribute set; provide them through a Kimi-supported
credential or environment mechanism outside the declarative store. If you set
`KIMI_CODE_HOME` to a different location, manage that location separately.

### CC Switch isolation

`programs.ccSwitch.enable = true` installs CC Switch as a native Nix source
build against Nixpkgs' WebKitGTK stack. No upstream AppImage or Debian package
is used. Home Manager atomically initializes `~/.cc-switch/settings.json`
with the English UI and an isolated Codex configuration directory at
`$XDG_STATE_HOME/cc-switch/codex`. The package sandbox also redirects Codex and
Agents state beneath `$XDG_STATE_HOME/cc-switch`, so CC Switch cannot take
ownership of the user's real `~/.codex` or `~/.agents` directories. Its entire
`XDG_CONFIG_HOME` view is backed by `$XDG_STATE_HOME/cc-switch/config`, and its
desktop-handler writes are isolated under `$XDG_STATE_HOME/cc-switch/applications`.
Consequently, CC Switch cannot modify the host's `mimeapps.list`, autostart
entries, or other XDG configuration.

The settings file remains mutable so CC Switch can preserve and update its
other device-local preferences. Home Manager seeds `language`,
`codexConfigDir`, the app-level window controls, the Codex-only homepage,
the hidden project switcher, and Alacritty as the preferred terminal only
when the settings file does not exist; existing settings are left untouched.
On Linux the initial defaults remove the native GTK title bar; the
application's own minimize, maximize, and close buttons remain available. The
launcher repeats the same create-if-missing initialization before every app
start, so a missing file is repaired even when `switch` reuses an unchanged
Home Manager generation. Existing files are never overwritten.
The package sandbox redirects both autostart and desktop-handler registration,
so neither can persist an unmanaged launch of the native binary in the user's
real XDG directories.

The `programs.ccSwitch.codexConfigDir` and `agentsConfigDir` options may select
other isolated locations; the package override mounts those exact paths into
its sandbox. The module rejects the user's shared `~/.codex` and `~/.agents`
directories. This keeps shared configuration ownership from becoming an
accidental declarative default.

## Codex Desktop Computer Use on NixOS

The NixSlop Codex Desktop package bundles the Linux Computer Use backend. Enable
its compositor-neutral system services separately in the NixOS configuration:

```nix
{
  imports = [ inputs.nixslop.nixosModules.codexComputerUse ];

  services.codexComputerUse = {
    enable = true;
    user = "user";
  };
}
```

This enables AT-SPI2 and ydotool without enabling GNOME Shell or selecting a
GNOME session. Set `user = null` when group membership is managed elsewhere.

When Codex Desktop and Hyprland Lua configuration are both enabled, the Home
Manager integration gives only `ydotoold-virtual-device` a US keymap. Physical
keyboards retain their configured layout. Opt out with:

```nix
programs.codexComputerUseHyprland.enable = false;
```

The opt-in `codex-desktop-computer-use-ui` output validates the Linux feature,
native-app, host-platform, and install-flow patches during its own build. With
the current Codex Desktop 26.727 renderer, the separate settings-card
availability patch is still an upstream `skipped-optional` path. The backend
and plugin remain installed, but UI visibility can therefore still depend on
the account/server rollout. NixSlop does not hide that limitation behind a
successful executable-only smoke test.

## Stable compatibility APIs

Existing individual imports and option paths remain supported:

| Integration | Individual module | Stable option |
| --- | --- | --- |
| OpenCode adapter | `homeManagerModules.openCode` | `programs.openCode.enable` |
| Codex Desktop | `homeManagerModules.codexDesktop` | `programs.codexDesktopLinux` |
| Hyprland virtual keyboard | `homeManagerModules.codexComputerUseHyprland` | `programs.codexComputerUseHyprland.enable` |
| Kimi Code | `homeManagerModules.kimiCode` | `programs.kimiCode` |
| Codex + OMX | `homeManagerModules.codexOmx` | `programs.codexOmx` |
| CC Switch | `homeManagerModules.ccSwitch` | `programs.ccSwitch` |
| Computer Use services | `nixosModules.codexComputerUse` | `services.codexComputerUse` |

`homeManagerModules.default`, `homeManagerModules.nixslop`, all ten public
package outputs, and the existing Codex Desktop override arguments form the
current compatibility boundary.

## Binary cache

```nix
nix.settings = {
  extra-substituters = [ "https://nixslop.cachix.org?priority=30" ];
  extra-trusted-public-keys = [
    "nixslop.cachix.org-1:Y41flUqIXb+Qx7D6hiugUE17RG4EkLaBn3UlVXc1oE8="
  ];
};
```

## Update your consumer

Home Manager:

```sh
nix flake update nixslop
home-manager switch
```

NixOS:

```sh
nix flake update nixslop
sudo nixos-rebuild switch --flake .#hostname
```

## Repository automation and design

Six fixed-target update workflows run daily on staggered UTC schedules. They
serialize through one mutex, fully validate the selected update, and merge only
through a target-specific `update/<target>` pull request. The stable
`Update Health` workflow checks the latest scheduled result for every lane;
Hermes should monitor that workflow name instead of a repository-wide “latest
run”. See [docs/updates.md](docs/updates.md) for schedules and failure behavior.

NixSlop remains a modular monorepo today so package dependencies, Home Manager
defaults, compatibility checks, and lock updates can change atomically. The
future split boundary and current component ownership are documented in
[docs/architecture.md](docs/architecture.md).
