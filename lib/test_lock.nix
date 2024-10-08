{ lock
, pkgs
, lib
, pyproject-nix
, ...
}: {
  inherit (builtins) removeAttrs;

  mkOverlay = {
    testWrongMetadataVersion = {
      expr = lock.mkOverlay {
        preferWheels = false;
        project = {
          pdmLock = {
            metadata = {
              lock_version = "3.0";
            };
          };
          pyproject = { };
        };
      };
      expectedError.type = "AssertionError";
    };

    testTrivial = {
      expr =
        let
          overlay = lock.mkOverlay {
            project = pyproject-nix.lib.project.loadPDMPyproject { projectRoot = ./fixtures/trivial; };
            preferWheels = false;
          };

          python = pkgs.python311.override {
            self = python;
            packageOverrides = overlay;
          };

        in
        rec {
          names = lib.attrNames (overlay python.pkgs python.pkgs);
          pkgs = map
            (attr:
              let
                drv = python.pkgs.${attr};
              in
              {
                inherit (drv) pname version;
              })
            (lib.filter (name: name != "__pdm2nix") names);
        };
      expected = {
        names = [ "__pdm2nix" "arpeggio" ];
        pkgs = [
          { pname = "arpeggio"; version = "2.0.2"; }
        ];
      };
    };

    testWithMarker = {
      # Colorama is only available for win32 according to it's marker.
      # Ensure that a package is skipped when it's marker indicates it shouldn't be available for a platform.
      expr =
        let
          overlay = lock.mkOverlay {
            project = pyproject-nix.lib.project.loadPDMPyproject { projectRoot = ./fixtures/with-marker; };
            preferWheels = false;
          };

          python = pkgs.python311.override {
            self = python;
            packageOverrides = lib.composeExtensions
              (_final: _prev: {
                colorama = null;
              })
              overlay;
          };

        in
        python.pkgs.colorama;
      expectedError.type = "ThrownError";
      expectedError.msg = "not supported for interpreter";
    };

    testKitchenSink = {
      expr =
        let
          overlay = lock.mkOverlay {
            project = pyproject-nix.lib.project.loadPDMPyproject { projectRoot = ./fixtures/kitchen-sink/a; };
            preferWheels = false;
          };

          python = pkgs.python311.override {
            self = python;
            packageOverrides = lib.composeExtensions overlay (_final: _prev: {
              # error: in pure evaluation mode, 'fetchMercurial' requires a Mercurial revision
              ruamel-yaml-clib = {
                pname = "ruamel-yaml-clib";
                version = "0.1.0";
              };
            });
          };

        in
        rec {
          names = lib.attrNames (overlay python.pkgs python.pkgs);
          pkgs = map
            (attr:
              let
                drv = python.pkgs.${attr};
              in
              {
                inherit (drv) pname version;
              })
            (lib.filter (name: name != "__pdm2nix") names);
        };
      expected = {
        names = [ "__pdm2nix" "arpeggio" "attrs" "b" "blinker" "c" "certifi" "charset-normalizer" "idna" "pip" "pyasn1-modules" "requests" "resolvelib" "ruamel-yaml-clib" "urllib3" ];
        pkgs = [
          { pname = "arpeggio"; version = "2.0.2"; }
          { pname = "attrs"; version = "23.1.0"; }
          { pname = "b"; version = "0.1.0"; }
          { pname = "blinker"; version = "1.6.2"; }
          { pname = "c"; version = "0.1.0"; }
          { pname = "certifi"; version = "2023.7.22"; }
          { pname = "charset-normalizer"; version = "3.3.2"; }
          { pname = "idna"; version = "3.4"; }
          { pname = "pip"; version = "20.3.1"; }
          { pname = "pyasn1-modules"; version = "0.0.0"; }
          { pname = "requests"; version = "2.31.0"; }
          { pname = "resolvelib"; version = "1.0.1"; }
          { pname = "ruamel-yaml-clib"; version = "0.1.0"; }
          { pname = "urllib3"; version = "2.0.7"; }
        ];
      };
    };

    testKitchenSinkPreferWheels = {
      expr =
        let
          overlay = lock.mkOverlay {
            project = pyproject-nix.lib.project.loadPDMPyproject { projectRoot = ./fixtures/kitchen-sink/a; };
            preferWheels = true;
          };

          python = pkgs.python311.override {
            self = python;
            packageOverrides = lib.composeExtensions overlay (_final: _prev: {
              # error: in pure evaluation mode, 'fetchMercurial' requires a Mercurial revision
              ruamel-yaml-clib = {
                pname = "ruamel-yaml-clib";
                version = "0.1.0";
              };
            });
          };

        in
        {
          isCorrectFile = lib.hasSuffix "Arpeggio-2.0.2-py2.py3-none-any.whl" "${python.pkgs.arpeggio.src}";
        };
      expected = {
        isCorrectFile = true;
      };
    };
  };

  mkPackage =
    let
      project = {
        pyproject = { };
      }; # Dummy empty project for tests

      callPackage = pkg:
        let
          py = pkgs.python311;

          drv = py.pkgs.callPackage pkg {
            buildPythonPackage = x: x; # No-op to return attrs

            __pdm2nix = {
              fetchPDMPackage = py.pkgs.callPackage lock.fetchPDMPackage { };
              environ = pyproject-nix.lib.pep508.mkEnviron py;
              pyVersion = pyproject-nix.lib.pep440.parseVersion py.version;
            };
          };

          # Remove stuff we can't assert equality for easily
          cleaned = removeAttrs drv [ "override" "overrideDerivation" ];
        in
        cleaned
        // {
          # Just extract names of dependencies for equality checking
          propagatedBuildInputs = map (drv: drv.pname) cleaned.propagatedBuildInputs;

          # Only get URLs from src
          src = drv.src.passthru;
        };
    in
    {
      testSimple = {
        expr = callPackage (lock.mkPackage { inherit project; } {
          files = [
            {
              file = "Arpeggio-2.0.0-py2.py3-none-any.whl";
              hash = "sha256:448e332deb0e9ccd04046f1c6c14529d197f41bc2fdb3931e43fc209042fbdd3";
            }
            {
              file = "Arpeggio-2.0.0.tar.gz";
              hash = "sha256:d6b03839019bb8a68785f9292ee6a36b1954eb84b925b84a6b8a5e1e26d3ed3d";
            }
          ];
          name = "arpeggio";
          summary = "Packrat parser interpreter";
          version = "2.0.0";
        });
        expected = {
          doCheck = false;
          format = "pyproject";
          meta = {
            description = "Packrat parser interpreter";
          };
          pname = "arpeggio";
          propagatedBuildInputs = [ ];
          version = "2.0.0";
          src = { };
        };
      };

      testWithDependencies = {
        expr = callPackage (lock.mkPackage { inherit project; } {
          dependencies = [
            "python-dateutil>=2.7.0"
            "typing-extensions; python_version < \"3.8\""
          ];
          files = [
            {
              file = "arrow-1.2.3-py3-none-any.whl";
              hash = "sha256:5a49ab92e3b7b71d96cd6bfcc4df14efefc9dfa96ea19045815914a6ab6b1fe2";
            }
            {
              file = "arrow-1.2.3.tar.gz";
              hash = "sha256:3934b30ca1b9f292376d9db15b19446088d12ec58629bc3f0da28fd55fb633a1";
            }
          ];
          name = "arrow";
          requires_python = ">=3.6";
          summary = "Better dates & times for Python";
          version = "1.2.3";
        });
        expected = {
          doCheck = false;
          format = "pyproject";
          meta = {
            description = "Better dates & times for Python";
          };
          pname = "arrow";
          propagatedBuildInputs = [ "python-dateutil" ];
          version = "1.2.3";
          src = { };
        };
      };

      testWithDependenciesOptionals = {
        expr = callPackage (lock.mkPackage { inherit project; } {
          dependencies = [
            "cachecontrol[filecache]"
          ];
          files = [
            {
              file = "arrow-1.2.3.tar.gz";
              hash = "sha256:3934b30ca1b9f292376d9db15b19446088d12ec58629bc3f0da28fd55fb633a1";
            }
          ];
          name = "dummy";
          requires_python = ">=3.6";
          summary = "Dummy test package";
          version = "1.2.3";
        });
        expected = {
          doCheck = false;
          format = "pyproject";
          meta = {
            description = "Dummy test package";
          };
          pname = "dummy";
          propagatedBuildInputs = [ "cachecontrol" "filelock" ];
          version = "1.2.3";
          src = { };
        };
      };
    };

  partitionFiles = {
    testSimple = {
      expr = lock.partitionFiles (builtins.head (lib.importTOML ./fixtures/trivial/pdm.lock).package).files;
      expected = {
        eggs = [ ];
        others = [ ];
        sdists = [
          {
            file = "Arpeggio-2.0.2.tar.gz";
            hash = "sha256:c790b2b06e226d2dd468e4fbfb5b7f506cec66416031fde1441cf1de2a0ba700";
          }
        ];
        wheels = [
          {
            file = "Arpeggio-2.0.2-py2.py3-none-any.whl";
            hash = "sha256:f7c8ae4f4056a89e020c24c7202ac8df3e2bc84e416746f20b0da35bb1de0250";
          }
        ];
      };
    };
  };

  fetchPDMPackage =
    let
      pyproject = lib.importTOML ./fixtures/kitchen-sink/a/pyproject.toml;
      pdmLock = lib.importTOML ./fixtures/kitchen-sink/a/pdm.lock;
      projectRoot = ./fixtures/kitchen-sink/a;
      fetchPDMPackage = pkgs.callPackage lock.fetchPDMPackage { };
      findPackage = name: lib.findFirst (pkg: pkg.name == name) (throw "package '${name} not found") pdmLock.package;
    in
    {
      testFetchFromLegacy = {
        expr =
          let
            src = (fetchPDMPackage {
              inherit pyproject projectRoot;
              package = findPackage "requests";
              filename = "requests-2.31.0.tar.gz";
            }).passthru;
          in
          src;
        expected = { };
      };

      testURL = {
        expr = (fetchPDMPackage {
          inherit pyproject projectRoot;
          package = findPackage "arpeggio";
          filename = "Arpeggio-2.0.2-py2.py3-none-any.whl";
        }).passthru;
        expected = {
          url = "https://files.pythonhosted.org/packages/f7/4f/d28bf30a19d4649b40b501d531b44e73afada99044df100380fd9567e92f/Arpeggio-2.0.2-py2.py3-none-any.whl";
        };
      };

      testMercurial = {
        expr = fetchPDMPackage {
          inherit pyproject projectRoot;
          package = findPackage "ruamel-yaml-clib";
        };
        expectedError.type = "Error";
        expectedError.msg = "requires a Mercurial revision";
      };

      testGit = {
        expr =
          let
            src = fetchPDMPackage {
              inherit pyproject projectRoot;
              package = findPackage "pip";
            };
          in
          assert lib.hasAttr "outPath" src;
          { inherit (src) ref allRefs submodules rev; };
        expected = {
          allRefs = true;
          ref = "refs/tags/20.3.1";
          rev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
          submodules = true;
        };
      };

      testPathSdist = {
        expr =
          let
            src = fetchPDMPackage {
              inherit pyproject projectRoot;
              package = findPackage "attrs";
              filename = "attrs-23.1.0.tar.gz";
            };
          in
          {
            isStorePath = lib.isStorePath "${src}";
            hasSuffix = lib.hasSuffix "attrs-23.1.0.tar.gz" "${src}";
          };
        expected = {
          isStorePath = true;
          hasSuffix = true;
        };
      };
    };
}
