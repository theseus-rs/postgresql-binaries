#!/usr/bin/env python3
"""Bundle the dependency closure of installed executables and loadable modules."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import sysconfig


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def is_binary(path, magic):
    with path.open("rb") as stream:
        return stream.read(4) in magic


def system_library(name, macos=False):
    if macos:
        return name.startswith(("/usr/lib/", "/System/Library/"))
    return bool(re.fullmatch(
        r"(?:ld-linux[^/]*|ld64)\.so(?:\.[0-9]+)*|ld-musl-[^/]+\.so\.1|"
        r"libc\.musl-[^/]+\.so\.1|lib(?:c|m|dl|pthread|rt|resolv|util|anl)\.so\.[0-9]+", name))


def bundle(root, macos):
    root = root.resolve()
    library_dir = root / "lib"
    library_dir.mkdir(exist_ok=True)
    magic = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe"} if macos else {b"\x7fELF"}
    initial = [p for p in root.rglob("*") if p.is_file() and not p.is_symlink() and is_binary(p, magic)]
    if not initial:
        raise RuntimeError("No installed binaries to audit")
    # Python's library is insufficient by itself: Py_Initialize also needs its
    # standard library and extension modules under the relocated prefix.
    python_origins = {}
    if any(p.name.startswith("plpython") for p in initial):
        stdlib = Path(sysconfig.get_path("stdlib"))
        shutil.copytree(stdlib, library_dir / stdlib.name, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("site-packages", "dist-packages", "__pycache__", "test", "tests"))
        initial = [p for p in root.rglob("*") if p.is_file() and not p.is_symlink() and is_binary(p, magic)]
        for p in initial:
            if p.is_relative_to(library_dir / stdlib.name):
                python_origins[p] = stdlib / p.relative_to(library_dir / stdlib.name)
    queue = list(initial)
    processed = set()
    origins = {}
    records = []
    system = set()
    search = [library_dir, Path("/lib"), Path("/usr/lib"), Path("/usr/local/lib")]
    search += list(Path("/lib").glob("*-linux-*")) + list(Path("/usr/lib").glob("*-linux-*"))
    search += list(Path("/usr/lib").glob("llvm*/lib"))
    initial_names = {p.name: p for p in initial if p.parent == library_dir}

    def resolve(name, binary):
        if macos:
            if name.startswith("@loader_path/"):
                return binary.parent / name[len("@loader_path/"):]
            if name.startswith("@executable_path/"):
                return root / "bin" / name[len("@executable_path/"):]
            if name.startswith("@rpath/"):
                tail = name[len("@rpath/"):]
                lines = run("otool", "-l", str(binary)).splitlines()
                for i, line in enumerate(lines):
                    if line.strip() == "cmd LC_RPATH":
                        path = lines[i + 2].strip().split(" ")[1]
                        path = path.replace("@loader_path", str(binary.parent)).replace("@executable_path", str(root / "bin"))
                        if (Path(path) / tail).is_file():
                            return Path(path) / tail
                if (library_dir / tail).is_file():
                    return library_dir / tail
                raise RuntimeError(f"Unresolved {name} in {binary}")
            return Path(name)
        if name in initial_names:
            return initial_names[name]
        rpaths = run("patchelf", "--print-rpath", str(binary)).split(":")
        candidates = [binary.parent] + [Path(p.replace("${ORIGIN}", str(binary.parent)).replace("$ORIGIN", str(binary.parent))) for p in rpaths if p] + search
        for directory in candidates:
            if (directory / name).is_file():
                return directory / name
        raise RuntimeError(f"Unresolved {name} in {binary}")

    while queue:
        binary = queue.pop(0)
        if binary in processed:
            continue
        processed.add(binary)
        binary.chmod(binary.stat().st_mode | 0o200)
        if macos:
            dependencies = [line.strip().split(" (", 1)[0] for line in run("otool", "-L", str(binary)).splitlines()[1:]]
            ids = run("otool", "-D", str(binary)).splitlines()[1:]
            dependencies = [dep for dep in dependencies if dep not in ids]
        else:
            dependencies = run("patchelf", "--print-needed", str(binary)).splitlines()
        for name in dependencies:
            if system_library(name, macos):
                system.add(name)
                continue
            source = resolve(name, origins.get(binary, python_origins.get(binary, binary))).resolve()
            if not source.is_file():
                raise RuntimeError(f"Missing {name} required by {binary}")
            if source.is_relative_to(root):
                destination = source
            else:
                # Keep the requested SONAME, even when its source is a symlink.
                destination = library_dir / Path(name).name
                if destination in origins and origins[destination] != source:
                    raise RuntimeError(f"Conflicting libraries named {destination.name}")
                if destination not in origins:
                    if destination.exists():
                        raise RuntimeError(f"Dependency overwrites installed file: {destination}")
                    shutil.copy2(source, destination)
                    origins[destination] = source
                    records.append({"file": str(destination.relative_to(root)), "source": str(source),
                                    "input_sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
                    queue.append(destination)
            if macos:
                relative = os.path.relpath(destination, binary.parent)
                subprocess.run(["install_name_tool", "-change", name, "@loader_path/" + relative, str(binary)], check=True)
        if macos:
            if ids:
                subprocess.run(["install_name_tool", "-id", "@loader_path/" + binary.name, str(binary)], check=True)
        else:
            relative = os.path.relpath(library_dir, binary.parent)
            subprocess.run(["patchelf", "--set-rpath", "$ORIGIN:$ORIGIN/" + relative, str(binary)], check=True)
    if macos:
        for binary in sorted(processed):
            subprocess.run(["codesign", "--force", "--sign", "-", str(binary)], check=True)
            for line in run("otool", "-L", str(binary)).splitlines()[1:]:
                name = line.strip().split(" (", 1)[0]
                if not system_library(name, True) and not name.startswith("@loader_path/"):
                    raise RuntimeError(f"Nonportable load command: {name} in {binary}")
    (root / "runtime-dependencies.json").write_text(json.dumps({
        "bundled": records, "system": sorted(system),
        "audited_files": sorted(str(p.relative_to(root)) for p in processed),
    }, indent=2) + "\n")


if __name__ == "__main__":
    bundle(Path(sys.argv[1]), sys.platform == "darwin")
