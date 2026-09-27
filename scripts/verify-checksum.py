#!/usr/bin/env python3
"""Verify exactly one named asset against a standard SHA-256 checksum file."""

import hashlib
from pathlib import Path
import re
import sys


def verify(asset, checksum):
    match = re.fullmatch(r"([0-9a-f]{64})  ([^\r\n/\\]+)\n?", checksum.read_text())
    if not match or match[2] != asset.name:
        raise ValueError(f"Invalid checksum record for {asset.name}")
    digest = hashlib.sha256()
    with asset.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != match[1]:
        raise ValueError(f"Digest mismatch: {asset.name}")
    print(f"{digest.hexdigest()}  {asset.name}")


if __name__ == "__main__":
    verify(Path(sys.argv[1]), Path(sys.argv[2]))
