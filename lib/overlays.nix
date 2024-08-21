{ lib, ... }:
let
  inherit (builtins) hasAttr;
in
lib.fix (self: {
  /*
    Return overlay `a` with `b` applied, but only with intersecting keys.

    Example:
      intersect (final: prev: { foo = 1; }) (final: prev: { foo = 1; bar = 2; })
    */
  intersect =
    # Overlay a
    a:
    # Overlay b
    b: (final: prev:
    let
      aApplied = a final prev;
    in
    (lib.composeExtensions a (self.filter (name: _: hasAttr name aApplied) b)) final prev);

  /*
    Return overlay filtered by predicate.

    Example:
      filter (name: overriden: name == "requests") (self: super: { })
    */
  filter = pred: overlay: (self: super: lib.filterAttrs pred (overlay self super));
})
