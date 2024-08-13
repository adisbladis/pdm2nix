{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";

    nixdoc.url = "github:nix-community/nixdoc";
    nixdoc.inputs.nixpkgs.follows = "nixpkgs";

    pyproject-nix.url = "github:adisbladis/pyproject.nix";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";

    mdbook-nixdoc.url = "github:adisbladis/mdbook-nixdoc";
    mdbook-nixdoc.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self
    , nixpkgs
    , nix-github-actions
    , flake-parts
    # , treefmt-nix
    , nixdoc
    , pyproject-nix
    , ...
    } @ inputs:
    let
      inherit (nixpkgs) lib;
    in
    flake-parts.lib.mkFlake
      { inherit inputs; }
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ];

        imports = [
          # inputs.treefmt-nix.flakeModule
        ];

        flake.githubActions = nix-github-actions.lib.mkGithubMatrix {
          checks = { inherit (self.checks) x86_64-linux; };
        };

        flake.lib = import ./lib {
          inherit pyproject-nix;
          inherit lib;
        };

        flake.templates =
          let
            root = ./templates;
            dirs = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir root));
          in
          lib.listToAttrs (
            map
              (
                dir:
                let
                  path = root + "/${dir}";
                  template = import (path + "/flake.nix");
                in
                lib.nameValuePair dir {
                  inherit path; inherit (template) description;
                }
              )
              dirs
          );

        # Expose unit tests for external discovery
        flake.libTests = import ./lib/test.nix {
          inherit lib pyproject-nix;
          pdm2nix = self.lib;
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        };

        perSystem =
          { pkgs
          , config
          , system
          , ...
          }:
          {
            checks = builtins.removeAttrs self.packages.${system} [ "default" ] // (
              import ./tests {
                inherit lib pyproject-nix pkgs;
                pdm2nix = self;
              }
            );

            devShells.default = pkgs.mkShell {
              packages =
                [
                  pkgs.hivemind
                  pkgs.mdbook
                  pkgs.reflex
                  pkgs.nix-unit
                  inputs.mdbook-nixdoc.packages.${system}.default
                  pkgs.pdm
                  pkgs.mercurial
                ]
                ++ self.packages.${system}.doc.nativeBuildInputs;
            };

            packages.doc = pkgs.callPackage ./doc {
              inherit self;
              nixdoc = nixdoc.packages.${system}.default;
              mdbook-nixdoc = inputs.mdbook-nixdoc.packages.${system}.default;
            };
          };
      };
}
