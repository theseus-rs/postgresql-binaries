#!/usr/bin/env bash

set -euo pipefail
script_directory=$(cd "$(dirname "$0")" && pwd)
exec "${PYTHON:-python3}" "$script_directory/collect-notices.py" "${1:?Usage: collect-notices.sh <install_directory>}"
