#!/usr/bin/env python3
"""Validate binary format, ABI and loader against the advertised target."""

import json
from pathlib import Path
import re
import struct
import subprocess
import sys


def elf_info(data):
    if data[:4] != b"\x7fELF" or data[4] not in (1, 2) or data[5] not in (1, 2):
        raise ValueError("Invalid ELF identification")
    bits = 64 if data[4] == 2 else 32
    endian = "little" if data[5] == 1 else "big"
    order = "<" if endian == "little" else ">"
    machine = struct.unpack_from(order + "H", data, 18)[0]
    flags = struct.unpack_from(order + "I", data, 48 if bits == 64 else 36)[0]
    phoff = struct.unpack_from(order + ("Q" if bits == 64 else "I"), data, 32 if bits == 64 else 28)[0]
    phsize, phnum = struct.unpack_from(order + "HH", data, 54 if bits == 64 else 42)
    interpreter = None
    for i in range(phnum):
        offset = phoff + i * phsize
        if struct.unpack_from(order + "I", data, offset)[0] == 3:
            start = struct.unpack_from(order + ("Q" if bits == 64 else "I"), data, offset + (8 if bits == 64 else 4))[0]
            interpreter = data[start:data.index(b"\0", start)].decode()
    return dict(bits=bits, endian=endian, machine=machine, flags=flags, interpreter=interpreter)


def validate(info, target, executable=False):
    for field in ("bits", "endian", "machine"):
        if info[field] != target[field]:
            raise ValueError(f"{field}: expected {target[field]}, got {info[field]}")
    if (executable or info["interpreter"]) and info["interpreter"] != target["interpreter"]:
        raise ValueError(f"Wrong ELF interpreter: {info['interpreter']}")
    if info["machine"] == 40:
        if info["flags"] >> 24 != 5:
            raise ValueError("ARM EABI5 required")
        if bool(info["flags"] & 0x400) != (target["float_abi"] == "hard"):
            raise ValueError("ARM float ABI mismatch")
    if info["machine"] == 8 and info["flags"] & 0x20:
        raise ValueError("MIPS N32 is incompatible with the advertised N64 ABI")
    if info["machine"] == 21 and info["flags"] & 3 != 2:
        raise ValueError("PowerPC64 ELFv2 ABI required")


def verify(root, target):
    if not target["enabled"]:
        raise ValueError("Target is quarantined pending compatible dependencies and CPU evidence")
    records = []
    for binary in sorted(root.rglob("*")):
        if not binary.is_file() or binary.is_symlink():
            continue
        data = binary.read_bytes()
        if data[:4] == b"\x7fELF":
            info = elf_info(data)
            validate(info, target, binary.name == "postgres")
            attributes = subprocess.check_output(["readelf", "-A", str(binary)], text=True)
            notes = subprocess.check_output(["readelf", "-n", str(binary)], text=True)
            if target["target"].startswith("x86_64") and re.search(r"x86-64-v[234]", notes):
                raise ValueError(f"CPU baseline exceeds x86-64: {binary}")
            info.update(file=str(binary.relative_to(root)), attributes=attributes, notes=notes)
            records.append(info)
        elif data[:2] == b"MZ":
            pe = struct.unpack_from("<I", data, 0x3c)[0]
            machine = struct.unpack_from("<H", data, pe + 4)[0]
            expected = 0xaa64 if target["target"].startswith("aarch64") else 0x8664
            if data[pe:pe + 4] != b"PE\0\0" or machine != expected:
                raise ValueError(f"Wrong PE architecture: {binary}")
            records.append(dict(file=str(binary.relative_to(root)), machine=machine))
        elif data[:4] in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
            architecture = "arm64" if target["target"].startswith("aarch64") else "x86_64"
            subprocess.run(["lipo", str(binary), "-verify_arch", architecture], check=True)
            commands = subprocess.check_output(["otool", "-l", str(binary)], text=True)
            versions = re.findall(r"^\s+minos (\d+\.\d+)", commands, re.M)
            versions += re.findall(r"cmd LC_VERSION_MIN_MACOSX\n\s+cmdsize \d+\n\s+version (\d+\.\d+)", commands)
            if not versions or any(tuple(map(int, version.split("."))) > (15, 0) for version in versions):
                raise ValueError(f"macOS deployment target exceeds 15.0: {binary}")
            records.append(dict(file=str(binary.relative_to(root)), architecture=architecture))
    if not records:
        raise ValueError("No binary files inspected")
    (root / "target-validation.json").write_text(json.dumps({"target": target, "files": records}, indent=2) + "\n")


if __name__ == "__main__":
    targets = json.loads((Path(__file__).parents[1] / "targets.json").read_text())
    verify(Path(sys.argv[1]), next(t for t in targets if t["target"] == sys.argv[2]))
