{ lib
, pyproject-nix
, ...
}:
let
  inherit (builtins) splitVersion head filter toJSON length;
  inherit (pyproject-nix.lib) pep508 pypa;
  inherit (lib) flatten filterAttrs attrValues;

  # Select the best compatible wheel from a list of wheels
  selectWheel = wheels: python:
    let
      compatibleWheels =
        let
          # Group wheel files by their file name
          wheelFilesByFileName = lib.listToAttrs (map (fileEntry: lib.nameValuePair fileEntry.file fileEntry) wheels);
          # Filter wheels based on interpreter
          selectedWheels = pypa.selectWheels python.stdenv.targetPlatform python (map (fileEntry: pypa.parseWheelFileName fileEntry.file) wheels);
        in
        map (wheel: wheelFilesByFileName.${wheel.filename}) selectedWheels;
    in
    if length compatibleWheels >= 1 then (head compatibleWheels) else throw "Could not find wheel for ${python.name}: ${toJSON wheels}";

  # Select the first sdist from a list of sdists
  selectSdist = head;

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
    }: (
      let
        inherit (self.partitionFiles files) wheels sdists;

        # Set default format
        format' =
          if length sdists > 0 then "pyproject"
          else if length wheels > 0 then "wheel"
          else throw "Could not compute default format for package '${name}' from files '${toJSON { inherit wheels sdists; }}'";

      in
      { python
      , pythonPackages
      , format ? format'
      }:
      let
        # Consider: How to avoid creating the PEP-508 environ for every package?
        environ = pep508.mkEnviron python;

      in
      {
        pname = name;
        inherit format version;

        # TODO: Invoke fetcher
        src =
          if format == "pyproject" then selectSdist sdists
          else if format == "wheel" then selectWheel python wheels
          else throw "Unhandled format: ${format}";

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

          # Mark as broken if Python version constraints don't match.
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
