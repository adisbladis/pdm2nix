{ lib, ... }:

{
  /*
    Make an editable package `pname` pointing to `path`.

    Note: To use this function `callPackage` it first, then call it with it's parameters.
    */
  mkEditablePackage =
    { python
    , runCommand
    , toPythonModule
    }:
    { pname
    , version
    , summary ? "Editable package ${pname}"
    , path
    , entrypoints ? { }
    }:
    toPythonModule (runCommand "${pname}-${version}"
      {
        inherit pname version;
      } ''
      mkdir -p "$out/${python.sitePackages}"
      cd "$out/${python.sitePackages}"

      # See https://docs.python.org/3.8/library/site.html for info on such .pth files
      # These add another site package path for each line
      echo '${toString path}' > ${pname}-editable.pth

      # Create a very simple egg so pkg_resources can find this package
      # See https://setuptools.readthedocs.io/en/latest/formats.html for more info on the egg format
      mkdir "${pname}.egg-info"
      cd "${pname}.egg-info"

      # Just enough standard PKG-INFO fields for an editable installation
      cat > PKG-INFO <<EOF
      Metadata-Version = "2.1";
      Name = ${pname};
      Version = ${version};
      Summary = ${summary};
      EOF

      ${lib.optionalString (entrypoints != { }) ''
        cat > entry_points.txt <<EOF
        ${lib.generators.toINI { } entrypoints}
        EOF
      ''}
    ''
    );
}
