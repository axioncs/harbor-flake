# harbor-flake

A Nix flake for [Harbor](https://github.com/harborstremio/harbor), a custom Stremio client, packaged from the official Linux `.deb` releases. Updated automatically.

## Usage

Add as a flake input:

```nix
{
  inputs.harbor = {
    url = "github:axioncs/harbor-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then reference the package, e.g. in `home.packages`:

```nix
home.packages = [ inputs.harbor.packages.${pkgs.stdenv.hostPlatform.system}.default ];
```

Or run it directly without installing:

```bash
nix run github:axioncs/harbor-flake
```

Or build it locally:

```bash
nix build github:axioncs/harbor-flake
./result/bin/harbor
```

## Channels

- `default` / `beta`: latest beta release
- `stable`: latest stable release

```bash
nix run github:axioncs/harbor-flake#stable
```

## Supported systems

- `x86_64-linux`

## License

Packaging code in this repo is MIT, see `LICENSE`. Harbor itself is MIT, see [upstream](https://github.com/harborstremio/harbor).
