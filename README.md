# NixSlop

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
