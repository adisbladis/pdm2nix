{ lib
, pyproject-nix
, editable
, ...
}:

lib.fix (self:
let
  inherit (builtins) hasAttr splitVersion head filter length nixVersion baseNameOf match pathExists;
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

  # Match str against a glob pattern
  matchGlob =
    let
      # Make regex from glob pattern
      mkRe = builtins.replaceStrings [ "*" ] [ ".*" ];
    in
    str: glob: match (mkRe glob) str != null;

  # Make the internal __pdm2nix overlay attribute.
  # This is used in the overlay to create PEP-508 environments & fetchers that don't need to be instantiated for every package.
  mkPdm2Nix = { python, callPackage }: {
    environ = pep508.mkEnviron python;
    fetchPDMPackage = python.pkgs.callPackage self.mkFetchPDMPackage {
      # Get from Flake attribute first, falling back to regular attribute access
      fetchFromPypi = pyproject-nix.fetchers.${python.system}.fetchFromPypi or pyproject-nix.fetchers.fetchFromPypi;
      fetchFromLegacy = pyproject-nix.fetchers.${python.system}.fetchFromLegacy or pyproject-nix.fetchers.fetchFromLegacy;
    };
    mkEditablePackage = callPackage editable.mkEditablePackage { };
  };

in
{
  /*
    Create package overlay from pdm.lock
    */
  mkOverlay =
    {
      # PDM project from pyproject.lib.project loadPDMPyproject
      project
    , # Whether to prefer prebuilt binary wheels over sdists
      preferWheels ? false
    ,
    }:
    let
      inherit (project.pdmLock) metadata;
      lockMajor = head (splitVersion metadata.lock_version);
    in
    assert project.pdmLock != null;
    assert lockMajor == "4";
    (final: prev:
    let
      pyVersion = pyproject-nix.lib.pep440.parseVersion prev.python.version;

      # Filter pdm.lock based on requires_python
      compatible = filter
        (package: ! hasAttr "requires_python" package || (
          lib.all
            (spec: pyproject-nix.lib.pep440.comparators.${spec.op} pyVersion spec.version)
            (pyproject-nix.lib.pep440.parseVersionConds package.requires_python)
        ))
        project.pdmLock.package;

      # Create package set
      pkgs = lib.listToAttrs (
        map
          (package: lib.nameValuePair package.name (
            # Route package depending on source:
            # - If a package is from pyproject.toml import it and call it directly
            # - If a package is a nested pyproject load it
            # - Otherwise generate purely from pdm.lock metadata
            let
              isEditable = hasAttr "editable" package;
              isPath = hasAttr "path" package;
              path = project.projectRoot + "/${package.path}";

              defaultNix = path + "/default.nix";
              hasNix = isPath && pathExists defaultNix;

              hasPyproject = isPath && pathExists "${path}/pyproject.toml";

            in
            if isEditable then
              (
                final.callPackage final.__pdm2nix.mkEditablePackage {
                  pname = package.name;
                  inherit (package) version;
                  inherit path;
                }
              )

            # If a package is from a local default.nix, callPackage the path directly
            else if hasNix then final.callPackage defaultNix { }

            # Import nested pyproject.toml
            else if hasPyproject then
              (
                final.callPackage
                  ({ buildPythonPackage, python }: buildPythonPackage (
                    (pyproject-nix.lib.project.loadPyprojectDynamic {
                      projectRoot = path;
                    }).renderers.buildPythonPackage
                      { inherit python; } // {
                      inherit (package) version;
                    }
                  ))
                  { }
              )

            # Package is from pdm.lock
            else (final.callPackage (self.mkPackage { inherit project preferWheels; } package) { })
          ))
          compatible
      );

    in
    {
      __pdm2nix = final.callPackage mkPdm2Nix { };
    } // pkgs);

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
       , # Project root path used for local file/directory sources
         projectRoot
       , # Filename for which to invoke fetcher
         filename ? throw "Missing argument filename"
       , # Parsed pyproject.toml contents
         pyproject
       }:
    let
      # Group list of files by their filename into an attrset
      filesByFileName = listToAttrs (map (file: nameValuePair file.file file) package.files);
      file = filesByFileName.${filename} or (throw "Filename '${filename}' not present in package");

    in
    if hasAttr "git" package then
      (
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
      )
    else if hasAttr "hg" package then
      (
        builtins.fetchMercurial
          {
            url = package.hg;
            rev = package.revision;
          }
      )
    else if hasAttr "url" package then
      (
        fetchurl {
          url = assert (baseNameOf package.url) == filename; package.url;
          inherit (file) hash;
        }
      )
    else if hasAttr "path" package then
      {
        outPath = projectRoot + "/${package.path}";
      }
    else
      (
        # Fetch from Pypi, either the public instance or a private one.
        let
          sources' = pyproject.tool.pdm.source or [ ];

          # Source from pyproject.toml keyed by their name
          sources = {
            # Default Pypi mirror as per https://pdm-project.org/latest/usage/config/.
            # If you want to omit the default PyPI index, just set the source name to pypi and that source will replace it.
            pypi = {
              url = "https://pypi.org/simple";
            };
          } // listToAttrs (map (source: nameValuePair source.name source) sources');

          # Filter only PyPi mirrors matching this package
          activeSources = filter
            (
              source: (
                (! hasAttr "include_packages" source || lib.any (matchGlob package.name) source.include_packages)
                &&
                (! hasAttr "exclude_packages" source || lib.all (glob: ! (matchGlob package.name) glob) source.exclude_packages)
              )
            )
            (attrValues sources);

        in
        if sources' == [ ] then
          (fetchFromPypi {
            pname = package.name;
            inherit (package) version;
            inherit (file) file hash;
          }) else
          (fetchFromLegacy {
            urls = map (source: source.url) activeSources;
            pname = package.name;
            inherit (file) file hash;
          })
      );

  /*
    Make package from pdm.lock contents
    */
  mkPackage =
    {
      # Project as returned by pyproject.lib.project.loadPDMPyProject
      project
    , # Whether to prefer prebuilt binary wheels over sdists
      preferWheels ? false
    ,
    }:
    # Package segment
    {
      # Package name string
      name
    , # Version string
      version
    , # Summary (description)
      summary
    , # Python interpreter PEP-440 constraints # List of PEP-508 strings
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
    , # Editable path
      editable ? false # deadnix: skip
    , # Python constraint
      requires_python ? "" # deadnix: skip
    }@package: (
      let
        inherit (self.partitionFiles files) wheels sdists eggs others;
      in
      { python
      , pythonPackages
      , callPackage
      , buildPythonPackage
      , __pdm2nix ? callPackage mkPdm2Nix { }
      , # Whether to prefer prebuilt binary wheels over sdists
        preferWheel ? preferWheels
      }:
      let
        # Select filename based on preference order.
        # By default we prefer sdists, but can optionally prefer to order wheels first.
        filenames =
          let
            selectedWheels = selectWheels wheels python;
            selectedSdists = map (file: file.file) sdists;
          in
          (
            if preferWheel then selectedWheels ++ selectedSdists
            else selectedSdists ++ selectedWheels
          ) ++ selectEggs eggs python ++ map (file: file.file) others;

        filename = head filenames;

        format =
          if length filenames == 0 then "pyproject"
          else if pypa.isSdistFileName filename then "pyproject"
          else if pypa.isWheelFileName filename then "wheel"
          else if pypa.isEggFileName filename then "egg"
          else throw "Could not infer format from filename '${filename}'";

        src = __pdm2nix.fetchPDMPackage {
          inherit (project) pyproject projectRoot;
          inherit package filename;
        };

      in
      buildPythonPackage
        {
          pname = name;
          inherit version src format;

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
          };
        }
      // optionalAttrs (format == "wheel") {
        # Don't strip prebuilt wheels
        dontStrip = true;
      }

    );
})
