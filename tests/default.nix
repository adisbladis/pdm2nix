{ lib
, pyproject-nix
, pdm2nix
, pkgs
,
}:
let
  callTest = path: args: import path (args // {
    inherit lib pyproject-nix pdm2nix;
  });

in
{
  trivial = callTest ./trivial {
    inherit (pkgs) python3;
  };
}
