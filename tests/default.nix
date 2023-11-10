{ lib
, pyproject-nix
, pdm2nix
, pkgs
}:
let
  callTest = path: args: import path (args // {
    python3 = args.python3 or pkgs.python3;
    inherit lib pyproject-nix pdm2nix overrides;
  });

  # A small set of overrides for packages used in tests.
  overrides = final: prev: {
    certifi = prev.certifi.overridePythonAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
    });

    idna = prev.idna.overridePythonAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.flit-core ];
    });

    urllib3 = prev.urllib3.overridePythonAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.hatchling ];
    });

    charset-normalizer = prev.charset-normalizer.overridePythonAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
    });

    requests = prev.requests.overridePythonAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
    });
  };

in
{
  trivial = callTest ./trivial { };
  nested = callTest ./nested { };
  nested-poetry = callTest ./nested-poetry { };
}
