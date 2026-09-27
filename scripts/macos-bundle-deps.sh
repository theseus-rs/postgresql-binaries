#!/usr/bin/env bash

set -euo pipefail
install_directory="${1:?Usage: macos-bundle-deps.sh <install_directory> [brew_prefix]}"
script_directory=$(cd "$(dirname "$0")" && pwd)
# Use the same interpreter as configure so the bundled stdlib matches PL/Python.
"${PYTHON:-python3}" "$script_directory/bundle-runtime.py" "$install_directory"
"${PYTHON:-python3}" "$script_directory/collect-notices.py" "$install_directory"
