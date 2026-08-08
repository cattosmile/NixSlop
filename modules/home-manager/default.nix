{ self }:

{
  imports = [
    self.homeManagerModules.codexComputerUse
    self.homeManagerModules.codexDesktop
    self.homeManagerModules.codexOmx
  ];
}
