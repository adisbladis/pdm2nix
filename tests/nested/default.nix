{ lib
, pyproject-nix
, pdm2nix
, python3
, overrides
}:
let
  project = pyproject-nix.lib.project.loadPDMPyproject {
    pyproject = lib.importTOML ./a/pyproject.toml;
  };

  python = python3.override {
    self = python;
    packageOverrides = lib.composeManyExtensions [
      (pdm2nix.lib.lock.mkOverlay {
        inherit (project) pyproject;
        pdmLock = lib.importTOML ./a/pdm.lock;
        projectRoot = ./a;
      })
      overrides
    ];
  };

in
python.pkgs.buildPythonPackage (
  project.renderers.buildPythonPackage { inherit python; } // {
    src = ./a;
  }
)
