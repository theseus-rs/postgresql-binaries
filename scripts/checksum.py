#!/usr/bin/env python3
"""Write portable SHA-256 checksum records, including on Windows runners."""

import hashlib
from pathlib import Path
import sys

for argument in sys.argv[1:]:
    path = Path(argument)
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    print(f"{digest}  {path.name}")
