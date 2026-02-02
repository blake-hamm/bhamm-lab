# NixOS

## Architecture Support

This flake supports both x86_64 and ARM (aarch64) architectures. Each host can explicitly declare its target architecture.

### Default Architecture

The default architecture is `x86_64-linux`, defined in [`nix/lib/default.nix`](../../nix/lib/default.nix). This is used as a fallback when a host doesn't specify a system.

### Per-Host Architecture

Each host configuration can specify its architecture by adding a `system` attribute:

```nix
# nix/hosts/myhost/default.nix
{
  system = "aarch64-linux";  # For ARM systems
  # or
  system = "x86_64-linux";   # For x86_64 systems

  deploy = { ... };
  ...
}
```


### Development Shells

The flake provides development shells for both architectures:

```bash
# x86_64 development shell
nix develop

# ARM development shell
nix develop .#aarch64-linux
```

## Deployment

```bash
# To rebuild:
colmena apply-local --sudo
colmena apply --on tail --impure

# https://nix-community.github.io/nixos-anywhere/

# To update flake
nix flake update
```

## Building ISO

```bash
nix build .#nixosConfigurations.minimal-iso.config.system.build.isoImage
```
