{ buildPythonPackage }:

buildPythonPackage {
  pname = "b";
  version = "0.1.0";
  src = ./.;
  format = "setuptools";
}
