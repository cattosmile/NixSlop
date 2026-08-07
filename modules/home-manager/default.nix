{ self }:

{
  imports = [
    self.homeManagerModules.codexDesktop
    self.homeManagerModules.codexOmx
  ];
}
