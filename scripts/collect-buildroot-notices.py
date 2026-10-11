#!/usr/bin/env python3
"""Attach Buildroot package ownership and checked license files to the audit."""
import csv
import json
from pathlib import Path
import shutil
import sys

output = Path(sys.argv[1]).resolve()
install = Path(sys.argv[2]).resolve()
sysroot = output / "target"
legal = output / "legal-info"
with (legal / "manifest.csv").open() as stream:
    packages = {row["PACKAGE"]: row for row in csv.DictReader(stream)}
owners = {}
for listing in (output / "build").glob("*/.files-list.txt"):
    for line in listing.read_text().splitlines():
        package, path = line.split(",", 1)
        owners[path.removeprefix("./")] = package

notices = install / "dependency-notices"
shutil.copytree(legal / "licenses", notices, dirs_exist_ok=True)
shutil.copy2(legal / "manifest.csv", notices / "manifest.csv")
report_path = install / "runtime-dependencies.json"
report = json.loads(report_path.read_text())
missing = []
for item in report["bundled"]:
    path = Path(item["source"]).relative_to(sysroot).as_posix()
    package = owners.get(path)
    metadata = packages.get(package)
    if metadata:
        item.update(package=package, package_version=metadata["VERSION"],
                    license=metadata["LICENSE"])
        folder = notices / (package + "-" + metadata["VERSION"])
        if not folder.is_dir() or not any(p.is_file() for p in folder.rglob("*")):
            missing.append(item["file"])
    else:
        missing.append(item["file"])
    item["source"] = "/" + path
report["missing_notices"] = missing
report["dependency_builder"] = "Buildroot 2026.08"
report_path.write_text(json.dumps(report, indent=2) + "\n")
if missing:
    raise SystemExit("Missing dependency notices: " + ", ".join(missing))
