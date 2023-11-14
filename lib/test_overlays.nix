{ lib
, overlays
, ...
}: {
  filter = {
    testName = {
      expr =
        let
          overlay = overlays.filter (name: _overriden: name == "foo") (
            _final: prev: {
              foo = 1;
              bar = prev.bar + 1;
            }
          );
        in
        lib.fix (final:
          overlay final {
            bar = 1;
          });
      expected = { foo = 1; };
    };

    testSuper = {
      expr =
        let
          overlay = overlays.filter (name: _overriden: name == "bar") (
            _final: prev: {
              foo = 1;
              bar = prev.bar + 1;
            }
          );
        in
        lib.fix (final:
          overlay final {
            bar = 1;
          });
      expected = { bar = 2; };
    };

    testSuperFilter = {
      expr =
        let
          overlay = overlays.filter (_name: overriden: overriden == 2) (
            _final: prev: {
              foo = 1;
              bar = prev.bar + 1;
            }
          );
        in
        lib.fix (final:
          overlay final {
            bar = 1;
          });
      expected = { bar = 2; };
    };
  };

  intersect = {
    testSimple = {
      expr =
        let
          a = _final: prev: { foo = prev.foo + 1; };
          b = _final: prev: {
            foo = prev.foo + 1;
            bar = prev.bar + 1;
          };
          overlay = overlays.intersect a b;
        in
        lib.fix (final:
          overlay final {
            foo = 1;
          });
      expected = {
        foo = 3;
      };
    };
  };
}
