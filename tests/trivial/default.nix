{ lib
, pyproject-nix
, pdm2nix
, python3
}:
let
  # Use project abstraction from pyproject.nix
  project = pyproject-nix.lib.project.loadPDMPyproject {
    pyproject = lib.importTOML ./pyproject.toml;
  };

  # Manage overlays
  overlay =
    let
      # Create overlay using pdm2nix
      overlay' = pdm2nix.lib.lock.mkOverlay {
        inherit (project) pyproject;
        pdmLock = lib.importTOML ./pdm.lock;
      };
      # Apply some build system fixes.
      # You should use overrides from poetry2nix, but to keep the test small
      # We opt to manually add them here.
    in
    lib.composeExtensions overlay' (final: prev: {
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
    });

  # Create an overriden interpreter
  python = python3.override {
    # Note the self argument.
    # It's important so the interpreter/set is internally consistent.
    self = python;
    # Pass composed Python overlay to the interpreter
    packageOverrides = overlay;
  };

in
# Call buildPythonPackage from the Python set
python.pkgs.buildPythonPackage (
  # Render a buildPythonPackage attrset with our overriden interpreter
  project.renderers.buildPythonPackage { inherit python; } // {
    # Set src to current directory.
    src = ./.;
  }
)
