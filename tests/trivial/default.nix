{ lib
, pyproject-nix
, pdm2nix
, python3
  # You should use overrides from poetry2nix, but to keep the test small
  # We opt to bundle a small set in the tests to keep the dependencies as small as possible.
, overrides
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
    in
    # Apply some build system fixes.
    lib.composeExtensions overlay' overrides;

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
