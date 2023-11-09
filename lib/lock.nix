{ lib
, pyproject-nix
, ...
}:
let
  inherit (builtins) hasAttr splitVersion head filter length nixVersion baseNameOf;
  inherit (pyproject-nix.lib) pep508 pypa;
  inherit (lib) flatten filterAttrs attrValues optionalAttrs listToAttrs nameValuePair versionAtLeast;

  # Select the best compatible wheel from a list of wheels
  selectWheels = wheels: python:
    let
      # Filter wheels based on interpreter
      compatibleWheels = pypa.selectWheels python.stdenv.targetPlatform python (map (fileEntry: pypa.parseWheelFileName fileEntry.file) wheels);
    in
    map (wheel: wheel.filename) compatibleWheels;

  # Select the best compatible egg from a list of eggs
  selectEggs = eggs: python: map (egg: egg.filename) (pypa.selectEggs python (map (egg: pypa.parseEggFileName egg.file) eggs));

  # Take the first element of a list, return null for empty
  optionalHead = list: if length list > 0 then head list else null;

in
lib.fix (self:
let
  # Make the internal __pdm2nix overlay attribute.
  # This is used in the overlay to create PEP-508 environments & fetchers that don't need to be instantiated for every package.
  mkPdm2Nix = python: {
    environ = pep508.mkEnviron python;
    fetchPDMPackage = python.pkgs.callPackage self.mkFetchPDMPackage {
      # Get from Flake attribute first, falling back to regular attribute access
      fetchFromPypi = pyproject-nix.fetchers.${python.system}.fetchFromPypi or pyproject-nix.fetchers.fetchFromPypi;
      fetchFromLegacy = pyproject-nix.fetchers.${python.system}.fetchFromLegacy or pyproject-nix.fetchers.fetchFromLegacy;
    };
    pyVersion = pyproject-nix.lib.pep440.parseVersion python.version;
  };

in
{
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
    assert lockMajor == "4";
    (final: prev:
    let
      # Internal metadata/fetchers
      __pdm2nix = mkPdm2Nix prev.python;

      # Filter pdm.lock based on requires_python
      compatible = filter
        (package: ! hasAttr "requires_python" package || (
          lib.all
            (spec: pyproject-nix.lib.pep440.comparators.${spec.op} __pdm2nix.pyVersion spec.version)
            (pyproject-nix.lib.pep440.parseVersionConds package.requires_python)
        ))
        pdmLock.package;

      # Create package set
      pkgs = lib.listToAttrs (map (package: lib.nameValuePair package.name (final.callPackage (self.mkPackage package) { })) compatible);

    in
    { inherit __pdm2nix; } // pkgs);

  /*
    Partition list of attrset from `package.files` into groups of sdists, wheels, eggs, and others
    */
  partitionFiles =
    # List of files from poetry.lock -> package segment
    files:
    let
      wheels = lib.lists.partition (f: pypa.isWheelFileName f.file) files;
      sdists = lib.lists.partition (f: pypa.isSdistFileName f.file) wheels.wrong;
      eggs = lib.lists.partition (f: pypa.isEggFileName f.file) sdists.wrong;
    in
    {
      sdists = sdists.right;
      wheels = wheels.right;
      eggs = eggs.right;
      others = eggs.wrong;
    };

  /*
    Fetch a package from pdm.lock
    */
  mkFetchPDMPackage =
    { fetchFromPypi
    , fetchurl
    , fetchFromLegacy
    }: {
         # The specific package segment from pdm.lock
         package
       , # Project root path used for local file sources
         projectRoot
       , # Filename for which to invoke fetcher
         filename ? throw "Missing argument filename"
       ,
       }:
    let
      # Group list of files by their filename into an attrset
      filesByFileName = listToAttrs (map (file: nameValuePair file.file file) package.files);
      file = filesByFileName.${filename} or (throw "Filename '${filename}' not present in package");

      format =
        if pypa.isSdistFileName filename then "pyproject"
        else if pypa.isWheelFileName filename then "wheel"
        else if pypa.isEggFileName filename then "egg"
        else throw "Could not infer format from filename '${filename}'";

    in
    if hasAttr "git" package then
      ((
        builtins.fetchGit
          {
            url = package.git;
            rev = package.revision;
          }
        // optionalAttrs (hasAttr "ref" package) {
          ref = "refs/tags/${package.ref}";
        }
        // optionalAttrs (versionAtLeast nixVersion "2.4") {
          allRefs = true;
          submodules = true;
        }
      ) // {
        passthru.format = "pyproject";
        format = "pyproject";
      })
    else if hasAttr "hg" package then
      ((
        builtins.fetchMercurial
          {
            url = package.hg;
            rev = package.revision;
          }
      ) // {
        passthru.format = "pyproject";
      })
    else if hasAttr "url" package then
      ((
        fetchurl {
          url = assert (baseNameOf package.url) == filename; package.url;
          inherit (file) hash;
        }
      ).overrideAttrs (
        old: {
          passthru = old.passthru // {
            inherit format;
          };
        }
      )
      )
    else if hasAttr "path" package then
      {
        format = "pyproject";
        outPath = projectRoot + "/${package.path}";
      }
    # TODO: Private PyPi repositories
    # else if (package in tool.pdm.source) (
    #   throw "Paths not implemented"
    # )
    else
      (
        fetchFromPypi {
          pname = package.name;
          inherit (package) version;
          inherit (file) file hash;
        }
      ).overrideAttrs (old: {
        passthru = old.passthru // {
          inherit format;
        };
      });

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
    , # URL string
      url ? null # deadnix: skip
    , # Path string
      path ? null # deadnix: skip
    , # Git ref
      ref ? null # deadnix: skip
    , # VCS revision
      revision ? null # deadnix: skip
    , # Git URL
      git ? null # deadnix: skip
    , # Mercurial URL
      hg ? null # deadnix: skip
    }@package: (
      let
        inherit (self.partitionFiles files) wheels sdists eggs;
      in
      { python
      , pythonPackages
      , buildPythonPackage
      , __pdm2nix ? mkPdm2Nix python
      }:
      let
        src = __pdm2nix.fetchPDMPackage {
          inherit package;
          projectRoot = null;
          filename = optionalHead (
            # TODO: Wheel preference and/or require wheel
            (map (file: file.file) sdists) ++ (selectWheels wheels python)
            ++ selectEggs eggs python
          );
        };

      in
      buildPythonPackage
        {
          pname = name;
          inherit version src;
          # inherit (src) format;

          inherit (src) format;

          doCheck = false; # No development deps in pdm.lock

          propagatedBuildInputs =
            let
              parsed = map pep508.parseString dependencies;
              # Filter only dependencies valid for this platform
              filtered = filter (dep: dep.markers == null || pep508.evalMarkers __pdm2nix.environ dep.markers) parsed;
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
            broken = ! (
              lib.all
                (spec: pyproject-nix.lib.pep440.comparators.${spec.op} __pdm2nix.pyVersion spec.version)
                (pyproject-nix.lib.pep440.parseVersionConds requires_python)
            );
          };
        }
      // optionalAttrs (src.format == "wheel") {
        # Don't strip prebuilt wheels
        dontStrip = true;
      }
    );
})
