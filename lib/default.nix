{ lib
, pyproject-nix
,
}:
let
  inherit (builtins) mapAttrs;
  inherit (lib) fix;
in
fix (self:
mapAttrs (_: path: import path ({ inherit lib pyproject-nix; } // self)) {
  editable = ./editable.nix;
  overlays = ./overlays.nix;
  lock = ./lock.nix;
})
