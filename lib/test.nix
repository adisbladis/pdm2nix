{ lib
, pdm2nix
, pkgs
, pyproject-nix
}:
let
  inherit (builtins) mapAttrs substring stringLength length attrNames;
  inherit (lib) mapAttrs' toUpper;

  capitalise = s: toUpper (substring 0 1 s) + (substring 1 (stringLength s) s);

  callTest = path: import path (pdm2nix // { inherit pkgs lib pyproject-nix; });
in
lib.fix (self: {
  editable = callTest ./test_editable.nix;
  overlays = callTest ./test_overlays.nix;
  lock = callTest ./test_lock.nix;

  # Yo dawg, I heard you like tests...
  #
  # Check that all exported modules are covered by a test suite with at least one test.
  coverage =
    mapAttrs
      (moduleName:
        mapAttrs' (sym: _: {
          name = "test" + capitalise sym;
          value = {
            expected = true;
            expr = self ? ${moduleName}.${sym} && length (attrNames self.${moduleName}.${sym}) >= 1;
          };
        }))
      pdm2nix;
})
