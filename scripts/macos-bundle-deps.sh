#!/usr/bin/env bash

set -euo pipefail
install_directory="${1:?Usage: macos-bundle-deps.sh <install_directory> [brew_prefix]}"
script_directory=$(cd "$(dirname "$0")" && pwd)
# PYTHON identifies the installation whose stdlib matches configured PL/Python.
bash "$script_directory/bundle-runtime.sh" "$install_directory"
bash "$script_directory/collect-notices.sh" "$install_directory"
