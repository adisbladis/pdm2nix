{ lib
, pyproject-nix
, pdm2nix
, python3
, overrides
}:
let
  project = pyproject-nix.lib.project.loadPDMPyproject {
    projectRoot = ./a;
  };

  python = python3.override {
    self = python;
    packageOverrides = lib.composeManyExtensions [
      (pdm2nix.lib.lock.mkOverlay { inherit project; })
      overrides
    ];
  };

in
python.pkgs.buildPythonPackage (
  project.renderers.buildPythonPackage { inherit python; }
)
