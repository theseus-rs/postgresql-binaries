#!/usr/bin/env python3
"""Make embedded Linux Python locate its stdlib relative to postgres."""

import hashlib
import json
from pathlib import Path
import sys


INITIALIZE = """\tif (getenv("PYTHONHOME") == NULL)
\t{
\t\tchar python_home[MAXPGPATH];

\t\t/* Python 3.11 cannot discover an embedded executable on Linux. */
\t\tstrlcpy(python_home, my_exec_path, sizeof(python_home));
\t\tget_parent_directory(python_home);
\t\tget_parent_directory(python_home);
\t\tif (setenv("PYTHONHOME", python_home, 0) != 0)
\t\t\tereport(FATAL, (errmsg("could not set bundled Python home: %m")));
\t}
\tPy_Initialize();
"""


def patch(source):
    record = source / "source-input.json"
    metadata = json.loads(record.read_text())
    if int(metadata["version"].split(".")[0]) < 15:
        return  # PL/Python is disabled in the PostgreSQL 14 build.
    path = source / "src/pl/plpython/plpy_main.c"
    original = path.read_text()
    needle = "\tPy_Initialize();\n"
    if original.count(needle) != 1 or 'getenv("PYTHONHOME")' in original:
        raise ValueError("Expected exactly one unpatched PL/Python initialization")
    modified = original.replace(needle, INITIALIZE)
    path.write_text(modified)
    metadata["packaging_patches"] = [{
        "script": "relocate-plpython.py",
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "file": str(path.relative_to(source)),
        "before_sha256": hashlib.sha256(original.encode()).hexdigest(),
        "after_sha256": hashlib.sha256(modified.encode()).hexdigest(),
    }]
    record.write_text(json.dumps(metadata, indent=2) + "\n")


if __name__ == "__main__":
    patch(Path(sys.argv[1]))
