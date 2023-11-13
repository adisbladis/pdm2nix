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
      (pdm2nix.lib.lock.mkOverlay { inherit project; preferWheels = false; })
      overrides
    ];
  };

in
python.withPackages (
  project.renderers.withPackages {
    inherit python;
    extras = [ "dev" ];
  }
)
