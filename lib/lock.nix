{ lib
, pyproject-nix
, ...
}:
let
  inherit (builtins) hasAttr splitVersion head filter toJSON length nixVersion baseNameOf;
  inherit (pyproject-nix.lib) pep508 pypa;
  inherit (lib) flatten filterAttrs attrValues optionalAttrs listToAttrs nameValuePair versionAtLeast;

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
    if length compatibleWheels >= 1
    then (head compatibleWheels)
    else throw "Could not find wheel for ${python.name}: ${toJSON wheels}";

  # Select the first sdist from a list of sdists
  selectSdist = head;
in
lib.fix (self: {
  /*
    Create package overlay from pdm.lock
    */
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

  /*
    Partition list of attrset from `package.files` into groups of wheels, sdist, and others
    */
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

  /*
    Make source derivation from pdm.lock package section contents
    */
  mkSrc =
    {
      # The specific package segment from pdm.lock
      package
    , # Parsed pyproject.toml
      pyproject
    , # Parsed pyproject.toml # Project root path used for local file sources
      projectRoot
    , # Filename for which to invoke fetcher
      filename ? throw "Missing argument filename"
    ,
    }:
    let
      # Group list of files by their filename into an attrset
      filesByFileName = listToAttrs (map (file: nameValuePair file.file file) package.files);
      file = filesByFileName.${filename} or (throw "Filename '${filename}' not present in package");
    in
    assert pyproject != { };
    if hasAttr "git" package then {
      fetcher = "fetchGit";
      args =
        {
          url = package.git;
          rev = package.revision;
          inherit (package) ref;
        }
        // optionalAttrs (versionAtLeast nixVersion "2.4") {
          allRefs = true;
          submodules = true;
        };
    }
    else if hasAttr "url" package then {
      fetcher = "fetchurl";
      args = {
        url = assert (baseNameOf package.url) == filename; package.url;
        inherit (file) hash;
      };
    }
    else if hasAttr "path" package then {
      fetcher = "none";
      args = projectRoot + "/${package.path}";
    }
    # TODO: Private PyPi repositories
    # else if (package in tool.pdm.source) (
    #   throw "Paths not implemented"
    # )
    else {
      fetcher = "fetchFromPypi";
      args = {
        pname = package.name;
        inherit (package) version;
        inherit (file) file hash;
      };
    };

  /*
    Make package from pdm.lock contents
    */
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
      let
        inherit (self.partitionFiles files) wheels sdists;

        # Set default format
        format' =
          if length sdists > 0
          then "pyproject"
          else if length wheels > 0
          then "wheel"
          else throw "Could not compute default format for package '${name}' from files '${toJSON {inherit wheels sdists;}}'";
      in
      { python
      , pythonPackages
      , format ? format'
      ,
      }:
      let
        # Consider: How to avoid creating the PEP-508 environ for every package?
        environ = pep508.mkEnviron python; # TODO: Fetcher factory for systems not exposed by pyproject-nix flake
      in
      {
        pname = name;
        inherit format version;

        doCheck = false; # No development deps in pdm.lock

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
      // optionalAttrs (format == "wheel") {
        # Don't strip prebuilt wheels
        dontStrip = format == "wheel";
      }
    );
})
