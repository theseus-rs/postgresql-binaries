#!/usr/bin/env python3
"""Record the actual installation's build inputs and configured features."""

import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import shutil

root = Path(sys.argv[1])
version, target = sys.argv[2:4]
revision = os.environ["BUILD_REVISION"]
if not re.fullmatch(r"[0-9a-f]{40}", revision):
    raise SystemExit("BUILD_REVISION must identify the checked-out build code")
pg_config = root / "bin" / ("pg_config.exe" if "windows" in target else "pg_config")
def config(option):
    return subprocess.check_output([str(pg_config), option], text=True).strip()

configure = config("--configure")
headers = list((root / "include").rglob("pg_config.h"))
header = "\n".join(p.read_text() for p in headers)
features = {name.lower(): bool(re.search(r"^#define USE_" + name + r" 1$", header, re.M))
            for name in ("ICU", "LLVM", "LZ4", "ZSTD", "OPENSSL", "LIBXML", "LIBXSLT")}
features["python"] = any((root / "lib").rglob("plpython3.*"))
features["bundled_timezone"] = any((root / "share").rglob("timezone/UTC"))
icu_data = root / "icu-data-input.json"
source = json.loads((root / "source-input.json").read_text())
result = {
    "schema_version": 1, "version": version, "target": target,
    "build_revision": revision, "source": source,
    "configure_flags": configure, "features": features,
    "toolchain": {"cc": config("--cc"), "cflags": config("--cflags"),
                  "ldflags": config("--ldflags"), "packaging_host": platform.platform()},
    "build_mode": "repackaged-edb" if "windows" in target else "source",
}
if icu_data.exists():
    result["icu_data_input"] = json.loads(icu_data.read_text())
if "windows" not in target:
    result["toolchain"]["compiler_version"] = subprocess.check_output(["cc", "--version"], text=True).splitlines()[0]
    result["runtime"] = json.loads((root / "runtime-dependencies.json").read_text())
else:
    result["runtime"] = {"system": ["Windows x64", "EDB-compatible Visual C++ runtime"],
                         "verification_limit": "EDB dependency closure and upstream toolchain are not independently rebuilt"}
if shutil.which("dpkg-query") and Path("/var/lib/dpkg/status").exists():
    result["toolchain"]["installed_packages"] = subprocess.check_output(["dpkg-query", "-W", "-f=${Package} ${Version}\n"], text=True).splitlines()
elif shutil.which("apk"):
    result["toolchain"]["installed_packages"] = subprocess.check_output(["apk", "info", "-v"], text=True).splitlines()
elif shutil.which("brew"):
    result["toolchain"]["installed_packages"] = subprocess.check_output(["brew", "list", "--versions"], text=True).splitlines()
(root / "build-manifest.json").write_text(json.dumps(result, indent=2) + "\n")
