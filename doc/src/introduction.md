# Introduction

## What is `pdm2nix`

`pdm2nix` takes a [PDM](https://pdm-project.org/) project as parsed by [pyproject.nix](https://nix-community.github.io/pyproject.nix) and generates a Python packages overlay.

The generated overlay can be plugged in to a [nixpkgs](https://github.com/nixos/nixpkgs) Python derivation to manage whole Nix Python package sets using PDM.

To use `pdm2nix` you first need to understand [pyproject.nix](https://nix-community.github.io/pyproject.nix/).
