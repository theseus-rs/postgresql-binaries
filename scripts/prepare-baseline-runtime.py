#!/usr/bin/env python3
"""Create a minimal runtime without the libraries that the archive must bundle."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

source = Path(sys.argv[1]).resolve()
destination = Path(sys.argv[2]).absolute()
if destination.exists():
    shutil.rmtree(destination)
destination.mkdir(parents=True)

# Absolute container symlinks must stay within the sysroot when read on the host.
for folder, directories, files in os.walk(source):
    for name in directories + files:
        path = Path(folder) / name
        if path.is_symlink():
            link = os.readlink(path)
            if link.startswith("/"):
                path.unlink()
                path.symlink_to(os.path.relpath(source / link.lstrip("/"), path.parent))

(destination / "bin").mkdir()
if b"INTERP" in subprocess.check_output(["readelf", "-l", str(source / "bin/busybox")]):
    raise SystemExit("The minimal runtime requires a static BusyBox")
shutil.copy2(source / "bin/busybox", destination / "bin/busybox")
for name in "sh ash awk cat chmod cp date dirname echo env find grep head hostname id ln ls mkdir mktemp mv printf pwd readlink rm sed sleep sort tail tar tee touch tr uname wc xargs".split():
    (destination / "bin" / name).symlink_to("busybox")

system_library = re.compile(
    r"^(?:libc\.so|(?:ld-linux[^/]*|ld64)\.so(?:\.[0-9]+)*|"
    r"(?:ld-musl-[^/]+|libc\.musl-[^/]+)\.so\.1|"
    r"lib(?:c|m|dl|pthread|rt|resolv|util|anl)\.so\.[0-9]+)$"
)
for directory in (source / "lib", source / "usr/lib"):
    for path in directory.iterdir():
        if system_library.fullmatch(path.name):
            target = destination / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            # Copy the real file at every ABI name, keeping this image independent
            # of build-time symlink layouts and development-only linker scripts.
            resolved = path.resolve()
            resolved.relative_to(source)
            shutil.copy2(resolved, target)

(destination / "etc").mkdir()
(destination / "etc/passwd").write_text("nobody:x:65534:65534:nobody:/tmp:/bin/sh\n")
(destination / "etc/group").write_text("nobody:x:65534:\n")
(destination / "etc/nsswitch.conf").write_text("passwd: files\ngroup: files\nhosts: files dns\n")
(destination / "tmp").mkdir(mode=0o1777)
(destination / "tmp").chmod(0o1777)
(destination / "usr/share/zoneinfo").mkdir(parents=True)
