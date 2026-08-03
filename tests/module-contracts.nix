{
  self,
  pkgs,
}:

let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  validUserFixture = {
    users.groups.module-test = { };
    users.users.module-test = {
      isNormalUser = true;
      group = "module-test";
    };
  };

  evalNixos =
    module: serviceConfig: extraModules:
    # Keep the nixpkgs source as a path value. String interpolation copies the
    # source to a second store path during fresh CI evaluation and can leave an
    # unrealised path context behind.
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      inherit pkgs system;
      modules = [
        module
        {
          boot.isContainer = true;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          system.stateVersion = "26.05";
          services.codexComputerUse = serviceConfig;
        }
      ]
      ++ extraModules;
    }).config;

  enabled = evalNixos self.nixosModules.codexComputerUse {
    enable = true;
    user = "module-test";
  } [ validUserFixture ];
  enabledThroughDefault = evalNixos self.nixosModules.default {
    enable = true;
    user = "module-test";
  } [ validUserFixture ];
  enabledWithoutUser = evalNixos self.nixosModules.codexComputerUse {
    enable = true;
    user = null;
  } [ ];
  disabled = evalNixos self.nixosModules.codexComputerUse {
    enable = false;
  } [ ];

  runtimeProjection = config: {
    atSpi = config.services.gnome.at-spi2-core.enable;
    ydotool = config.programs.ydotool.enable;
    userGroups = config.users.users."module-test".extraGroups;
  };
in
assert builtins.isString enabled.system.build.toplevel.drvPath;
assert builtins.isString enabledThroughDefault.system.build.toplevel.drvPath;
assert enabled.services.gnome.at-spi2-core.enable;
assert enabled.programs.ydotool.enable;
assert lib.elem "ydotool" enabled.users.users."module-test".extraGroups;
# `nixosModules.default` is a public behavioral alias. Compare evaluated
# behavior, never module functions (which are not meaningfully comparable).
assert runtimeProjection enabledThroughDefault == runtimeProjection enabled;
assert enabledWithoutUser.services.codexComputerUse.user == null;
assert !(builtins.hasAttr "module-test" enabledWithoutUser.users.users);
assert !disabled.services.gnome.at-spi2-core.enable;
assert !disabled.programs.ydotool.enable;
true
