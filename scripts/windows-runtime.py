#!/usr/bin/env python3
"""Bundle EDB's matching PL/Python runtime and audit PE module imports."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import sys


def imports(data):
    if data[:2] != b"MZ":
        return []
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("Invalid PE signature")
    sections = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    optional = pe + 24
    magic = struct.unpack_from("<H", data, optional)[0]
    directory = optional + (112 if magic == 0x20b else 96)
    import_rva = struct.unpack_from("<I", data, directory + 8)[0]
    def offset(rva):
        for i in range(sections):
            section = optional + optional_size + i * 40
            size, start, raw_size, raw = struct.unpack_from("<IIII", data, section + 8)
            if start <= rva < start + max(size, raw_size):
                return raw + rva - start
        raise ValueError("PE import RVA outside sections")
    result = []
    def add_name(rva):
        start = offset(rva)
        name = data[start:data.index(b"\0", start)].decode("ascii").lower()
        if not re.fullmatch(r"[a-z0-9_.+-]+", name):
            raise ValueError("Invalid imported DLL name")
        result.append(name)
    if import_rva:
        cursor = offset(import_rva)
        while any(data[cursor:cursor + 20]):
            add_name(struct.unpack_from("<I", data, cursor + 12)[0])
            cursor += 20
    # Delay-loaded DLLs are runtime dependencies too.
    delay_rva = struct.unpack_from("<I", data, directory + 13 * 8)[0]
    if delay_rva:
        image_base = struct.unpack_from("<Q" if magic == 0x20b else "<I", data,
                                        optional + (24 if magic == 0x20b else 28))[0]
        cursor = offset(delay_rva)
        while any(data[cursor:cursor + 32]):
            attributes, name = struct.unpack_from("<II", data, cursor)
            add_name(name if attributes & 1 else name - image_base)
            cursor += 32
    return result


def python_version(root):
    versions = set()
    for path in (root / "lib").glob("*plpython*.dll"):
        for name in imports(path.read_bytes()):
            match = re.fullmatch(r"python(3)(\d+)\.dll", name)
            if match:
                versions.add(f"{match[1]}.{match[2]}")
    if len(versions) != 1:
        raise ValueError(f"Expected one EDB Python ABI, found {versions}")
    return versions.pop()


def bundle(root):
    expected = python_version(root)
    if expected != f"{sys.version_info.major}.{sys.version_info.minor}":
        raise ValueError("Selected Python does not match EDB's imported DLL")
    prefix = Path(sys.base_prefix)
    destination = root / "bin"
    shutil.copytree(prefix / "Lib", destination / "Lib", dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("site-packages", "__pycache__", "test", "tests"))
    shutil.copytree(prefix / "DLLs", destination / "DLLs", dirs_exist_ok=True)
    # Preserve hashes for upstream PE dependencies as well as newly added Python.
    records = [{"file": str(p.relative_to(root)), "source": "EDB input archive",
                "input_sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
               for p in root.rglob("*.dll") if "plperl" not in p.name and "pltcl" not in p.name]
    for path in [*prefix.glob("python*.dll"), prefix / "python.exe"]:
        shutil.copy2(path, destination / path.name)
        records.append({"file": "bin/" + path.name, "source": str(path), "input_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                        "package": "CPython", "package_version": sys.version.split()[0]})
    notices = root / "dependency-notices" / "python"
    notices.mkdir(parents=True, exist_ok=True)
    shutil.copy2(prefix / "LICENSE.txt", notices / "LICENSE.txt")
    # EDB also includes language-pack modules without their Perl/Tcl runtimes.
    # Match the Unix package's explicit no-Perl/no-Tcl feature selection.
    for directory in (root / "lib", root / "share" / "extension"):
        for path in directory.iterdir():
            if path.is_file() and ("plperl" in path.name or "pltcl" in path.name):
                path.unlink()
    required_notices = ["server_license.txt", "commandlinetools_3rd_party_licenses.txt"]
    if (destination / "stackbuilder.exe").exists():
        required_notices.append("StackBuilder_3rd_party_licenses.txt")
    missing_notices = [name for name in required_notices if not (root / name).is_file()]
    if missing_notices:
        raise ValueError(f"Missing EDB redistribution notices: {missing_notices}")
    data = {"bundled": records, "system": ["Windows x64", "Microsoft Visual C++ runtime (vcruntime140 family)"],
            "missing_notices": missing_notices, "disabled_features": ["Perl", "Tcl"],
            "python_input": {"version": sys.version, "provider": "actions/setup-python hosted toolcache", "abi": expected}}
    system = set("kernel32 user32 advapi32 bcrypt ncrypt secur32 shell32 shlwapi crypt32 cryptbase normaliz winmm winspool rpcrt4 netapi32 iphlpapi dbghelp psapi imm32 usp10 dwmapi mswsock winhttp ws2_32 wsock32 ntdll ole32 oleaut32 comdlg32 gdi32 msvcrt ucrtbase version powrprof setupapi dnsapi wldap32 hid comctl32 cabinet userenv authz wintrust imagehlp shcore pdh delayimp avrt msimg32 oleacc uxtheme".split())
    audited = []
    for binary in root.rglob("*"):
        if binary.suffix.lower() not in (".exe", ".dll", ".pyd"):
            continue
        for name in imports(binary.read_bytes()):
            if name.removesuffix(".dll").removesuffix(".drv") in system or name.startswith(("api-ms-win-", "ext-ms-win-", "vcruntime140", "msvcp140")):
                continue
            directories = (binary.parent, destination, destination / "DLLs")
            if not any(any(p.name.lower() == name for p in directory.iterdir()) for directory in directories):
                raise ValueError(f"Unbundled DLL {name} imported by {binary}")
        audited.append(str(binary.relative_to(root)))
    data["audited_files"] = audited
    (root / "runtime-dependencies.json").write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    root = Path(sys.argv[2])
    if sys.argv[1] == "detect":
        print("version=" + python_version(root))
    else:
        bundle(root)
