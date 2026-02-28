{
  description = "Wizarr - media server invitation and onboarding manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system} = rec {
      wizarr = pkgs.callPackage ./package.nix { };
      default = wizarr;
    };

    nixosModules = rec {
      wizarr = { lib, pkgs, ... }: {
        imports = [ ./module.nix ];
        services.wizarr.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.wizarr;
      };
      default = wizarr;
    };
  };
}
