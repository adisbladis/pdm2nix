{ lib
, pyproject-nix
, ...
}:
let
  inherit (builtins) splitVersion head filter;
  inherit (pyproject-nix.lib) pep508 pypa;
  inherit (lib) flatten filterAttrs attrValues;
in
lib.fix (self: {
  /* Create package overlay from pdm.lock */
  mkOverlay =
    # Parsed pdm.lock
    pdmLock:
    let
      inherit (pdmLock) metadata;
      lockMajor = head (splitVersion metadata.lock_version);
    in
    assert lockMajor == "4"; {
      # TODO: The rest of the fucking owl
    };

  /* Partition list of attrset from `package.files` into groups of wheels, sdist, and others */
  partitionFiles =
    # List of files from poetry.lock -> package segment
    files:
    let
      wheels = lib.lists.partition (f: pypa.isWheelFileName f.file) files;
      sdists = lib.lists.partition (f: pypa.isSdistFileName f.file) wheels.wrong;
    in
    {
      wheels = wheels.right;
      sdists = sdists.right;
      others = sdists.wrong;
    };

  /* Make package from pdm.lock contents */
  mkPackage =
    {
      # Package name string
      name
    , # Version string
      version
    , # Summary (description)
      summary
    , # Python interpreter PEP-440 constraints
      requires_python ? ""
    , # List of PEP-508 strings
      dependencies ? [ ]
    , # List of attrset with files
      files ? [ ]
    ,
    }: (
      { python
      , pythonPackages
      , fetchPypi
        # Consider: Is this actually a good API? Is there another better way to accomplish it?
      , preferWheel ? false
      }:
      let
        # Consider: How to avoid creating the PEP-508 environ for every package?
        environ = pep508.mkEnviron python;

        # Filter and put sources into preference order
        srcFiles =
          let
            inherit (self.partitionFiles files) wheels sdists others;
            # Filter wheels not compatible with this environment.
            # This also puts them in preference order.
            compatibleWheels =
              let
                # Group wheel files by their file name
                wheelFilesByFileName = lib.listToAttrs (map (fileEntry: lib.nameValuePair fileEntry.file fileEntry) wheels);
                # Filter wheels based on interpreter
                selectedWheels = pypa.selectWheels python.stdenv.targetPlatform python (map (fileEntry: pypa.parseWheelFileName fileEntry.file) wheels);
              in
              map (wheel: wheelFilesByFileName.${wheel.filename}) selectedWheels;
          in
          (if preferWheel then compatibleWheels ++ sdists else sdists ++ compatibleWheels) ++ others;

      in
      assert srcFiles != [ ]; {
        pname = name;
        inherit version;

        # TODO: Actually select sources and invoke fetcher
        src = null;

        propagatedBuildInputs =
          let
            parsed = map pep508.parseString dependencies;
            # Filter only dependencies valid for this platform
            filtered = filter (dep: dep.markers == null || pep508.evalMarkers environ dep.markers) parsed;
          in
          flatten (map
            (dep:
              let
                # Optional dependencies filtered by enabled groups
                optionals = attrValues (filterAttrs (group: _: lib.elem group dep.extras) (pythonPackages.${dep.name}.optional-dependencies or { }));
              in
              [ pythonPackages.${dep.name} ] ++ optionals)
            filtered);

        meta = {
          description = summary;
          broken =
            let
              pyVersion = pyproject-nix.lib.pep440.parseVersion python.version;
            in
              ! (
                lib.all
                  (spec: pyproject-nix.lib.pep440.comparators.${spec.op} pyVersion spec.version)
                  (pyproject-nix.lib.pep440.parseVersionConds requires_python)
              );
        };
      }
    );
})
