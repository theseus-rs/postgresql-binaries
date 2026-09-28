#!/usr/bin/env python3
"""Preserve installed dependency notices and report any missing source notices."""

import json
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(sys.argv[1])
data = json.loads((root / "runtime-dependencies.json").read_text())
notices = root / "dependency-notices"
notices.mkdir(exist_ok=True)
missing = []
for item in data["bundled"]:
    source = Path(item["source"])
    paths = []
    if shutil.which("dpkg-query") and Path("/var/lib/dpkg/status").is_file():
        # Debian's merged-/usr paths may differ from dpkg's recorded spelling.
        for spelling in [str(source), str(source).removeprefix("/usr")]:
            result = subprocess.run(["dpkg-query", "-S", spelling], capture_output=True, text=True)
            if result.returncode == 0:
                package = result.stdout.split(": ", 1)[0]
                item["package"] = package
                item["package_version"] = subprocess.check_output(["dpkg-query", "-W", "-f=${Version}", package], text=True)
                paths = [Path("/usr/share/doc") / package.split(":")[0] / "copyright"]
                break
    elif sys.platform == "darwin":
        # Homebrew retains source notices at each Cellar formula's version root.
        for parent in source.parents:
            if parent.parent.parent.name == "Cellar":
                item["package"] = parent.parent.name
                item["package_version"] = parent.name
                paths = [p for p in parent.rglob("*") if p.is_file() and
                         p.name.upper().startswith(("LICENSE", "COPYING", "NOTICE", "COPYRIGHT"))]
                break
    else:
        result = subprocess.run(["apk", "info", "--who-owns", str(source)], capture_output=True, text=True, check=True)
        item["package"] = result.stdout.strip().split(" owned by ")[-1]
        paths = list(Path("/usr/share/licenses").glob("**/*")) if Path("/usr/share/licenses").exists() else []
    paths = [p for p in paths if p.is_file()]
    if not paths:
        missing.append(item["file"])
    for index, path in enumerate(paths):
        folder = notices / item.get("package", source.name).replace(":", "_")
        folder.mkdir(exist_ok=True)
        shutil.copy2(path, folder / f"{index}-{path.name}")
data["missing_notices"] = missing
(root / "runtime-dependencies.json").write_text(json.dumps(data, indent=2) + "\n")
if missing:
    print("Missing dependency notices; release is blocked: " + ", ".join(missing), file=sys.stderr)
