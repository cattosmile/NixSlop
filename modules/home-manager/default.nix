{ self }:

{
  imports = [
    self.homeManagerModules.openCode
    self.homeManagerModules.codexDesktop
    self.homeManagerModules.kimiCode
    self.homeManagerModules.codexOmx
  ];
}
