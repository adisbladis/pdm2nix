{
  description = "A basic flake using pdm2nix";

  inputs.pyproject-nix.url = "github:nix-community/pyproject.nix";
  inputs.pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";

  inputs.pdm2nix.url = "github:adisbladis/pdm2nix";
  inputs.pdm2nix.inputs.pyproject-nix.follows = "pyproject-nix";
  inputs.pdm2nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, pyproject-nix, pdm2nix, ... }:
    let
      inherit (nixpkgs) lib;

      # Use project abstraction from pyproject.nix
      project = pyproject-nix.lib.project.loadPDMPyproject {
        projectRoot = ./.;
      };

      # Manage overlays
      overlay =
        let
          # Create overlay using pdm2nix
          overlay' = pdm2nix.lib.lock.mkOverlay {
            inherit project;

            # Use sdists over binary wheels.
            #
            # This is less likely to work out of the box than `preferWheels = true`,
            # but comes with significant trade-offs.
            preferWheels = false;
          };

          # Pdm2nix can only work with what it has, and pdm.lock is missing essential metadata to perform some builds.
          # Some notable metadata missing is:
          # - PEP-517 build-systems
          # - Native dependencies
          #
          # The poetry2nix project has existing overlays you can use that fixes a lot of common issues, but you might
          # need to supplement your own.
          #
          # See https://nixos.org/manual/nixpkgs/stable/#python section on overriding Python packages.
          overrides = _final: _prev: { };
        in
        lib.composeExtensions overlay' overrides;

      # This example is only using x86_64-linux
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      # Create an overriden interpreter
      python = pkgs.python3.override {
        # Note the self argument.
        # It's important so the interpreter/set is internally consistent.
        self = python;
        # Pass composed Python overlay to the interpreter
        packageOverrides = overlay;
      };

    in
    {
      devShells.x86_64-linux.default =
        let
          # Render a withPackages function with our overriden interpreter
          arg = project.renderers.withPackages { inherit python; };
          # And pass it to the interpreter function withPackages
          pythonEnv = python.withPackages arg;
        in
        pkgs.mkShell {
          packages = [ pythonEnv ];
        };

      packages.x86_64-linux.default =
        let
          # Render a buildPythonPackage attrset with our overriden interpreter
          attrs = project.renderers.buildPythonPackage { inherit python; };
        in
        # Call buildPythonPackage from the Python set
        python.pkgs.buildPythonPackage attrs;
    };
}
