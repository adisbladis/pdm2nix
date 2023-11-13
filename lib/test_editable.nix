{ lib
, editable
, ...
}:

let
  # Fake callPackage
  mkEditablePackage = editable.mkEditablePackage {
    python = {
      sitePackages = "site-packages";
    };
    runCommand = name: attrs: command: {
      inherit attrs command;
    };
    toPythonModule = x: x;
  };


in
{
  mkEditablePackage = {
    testBasic = {
      expr = mkEditablePackage {
        pname = "basic";
        version = "0.1.0";
        path = "/build/foo";
      };
      expected = {
        attrs = {
          pname = "basic";
          version = "0.1.0";
        };
        command = "mkdir -p \"$out/site-packages\"\ncd \"$out/site-packages\"\n\n# See https://docs.python.org/3.8/library/site.html for info on such .pth files\n# These add another site package path for each line\necho '/build/foo' > basic-editable.pth\n\n# Create a very simple egg so pkg_resources can find this package\n# See https://setuptools.readthedocs.io/en/latest/formats.html for more info on the egg format\nmkdir \"basic.egg-info\"\ncd \"basic.egg-info\"\n\n# Just enough standard PKG-INFO fields for an editable installation\ncat > PKG-INFO <<EOF\nMetadata-Version = \"2.1\";\nName = basic;\nVersion = 0.1.0;\nSummary = Editable package basic;\nEOF\n\n\n";
      };
    };

    testWithEntryPoints = {
      expr = mkEditablePackage {
        pname = "basic";
        version = "0.1.0";
        path = "/build/foo";
        entrypoints = {
          foo.bar = "baz";
        };
      };
      expected = {
        attrs = {
          pname = "basic";
          version = "0.1.0";
        };
        command = "mkdir -p \"$out/site-packages\"\ncd \"$out/site-packages\"\n\n# See https://docs.python.org/3.8/library/site.html for info on such .pth files\n# These add another site package path for each line\necho '/build/foo' > basic-editable.pth\n\n# Create a very simple egg so pkg_resources can find this package\n# See https://setuptools.readthedocs.io/en/latest/formats.html for more info on the egg format\nmkdir \"basic.egg-info\"\ncd \"basic.egg-info\"\n\n# Just enough standard PKG-INFO fields for an editable installation\ncat > PKG-INFO <<EOF\nMetadata-Version = \"2.1\";\nName = basic;\nVersion = 0.1.0;\nSummary = Editable package basic;\nEOF\n\ncat > entry_points.txt <<EOF\n[foo]\nbar=baz\n\nEOF\n\n";
      };
    };
  };
}
