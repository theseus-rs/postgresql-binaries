#!/usr/bin/env python3
"""Write portable SHA-256 checksum records, including on Windows runners."""

import hashlib
from pathlib import Path
import sys

for argument in sys.argv[1:]:
    path = Path(argument)
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    # Emit the same LF-delimited bytes even under Windows Python 3.9.
    sys.stdout.buffer.write(f"{digest.hexdigest()}  {path.name}\n".encode("utf-8"))
