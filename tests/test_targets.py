import importlib.util
import json
from pathlib import Path
import re
import shutil
import struct
import tempfile
import unittest

root = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location("target", root / "scripts/verify-target.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
targets = json.loads((root / "targets.json").read_text())


class TargetTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("readelf"), "GNU readelf is required")
    def test_glibc_requirement_floor(self):
        for version, definition in (("2.35", False), ("2.36", False),
                                    ("2.37", False), ("2.44", False), ("2.44", True)):
            with self.subTest(version=version, definition=definition), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory)
                section_name = b".gnu.version_d" if definition else b".gnu.version_r"
                strings = b"\0libc.so.6\0GLIBC_" + version.encode() + b"\0.dynstr\0" + section_name + b"\0"
                offset = (256 + len(strings) + 3) & ~3
                header = struct.pack("<16sHHIQQQIHHHHHH", b"\x7fELF\x02\x01\x01",
                                     3, 62, 1, 0, 0, 64, 0, 64, 0, 0, 64, 3, 1)
                if definition:
                    contents = struct.pack("<HHHHIII", 1, 0, 2, 1, 0, 20, 0) + struct.pack("<II", 11, 0)
                else:
                    contents = struct.pack("<HHIII", 1, 1, 1, 16, 0) + struct.pack("<IHHII", 0, 0, 2, 11, 0)
                names = struct.pack("<IIQQQQIIQQ", strings.index(b".dynstr"), 3, 0, 0, 256, len(strings), 0, 0, 1, 0)
                section = struct.pack("<IIQQQQIIQQ", strings.index(section_name),
                                      0x6ffffffd if definition else 0x6ffffffe,
                                      0, 0, offset, len(contents), 1, 1, 4, 0)
                (archive / "fixture.so").write_bytes(header + bytes(64) + names + section + strings +
                                                     bytes(offset - 256 - len(strings)) + contents)
                target = dict(next(t for t in targets if t["id"] == "x86_64-unknown-linux-gnu"), glibc_max_version="2.36")
                if not definition and version in ("2.37", "2.44"):
                    with self.assertRaisesRegex(ValueError, "GLIBC requirement exceeds 2.36"):
                        module.verify(archive, target)
                else:
                    module.verify(archive, target)
                    report = json.loads((archive / "target-validation.json").read_text())
                    self.assertEqual(report["files"][0]["required_glibc_versions"], [] if definition else [version])

    @unittest.skipUnless(shutil.which("readelf"), "GNU readelf is required")
    def test_x86_required_and_optional_isa_notes(self):
        # Minimal ELF64 files with real GNU property notes, decoded by readelf.
        # NEEDED is mandatory hardware support; USED may describe CPU dispatch.
        for needed, used in ((1, None), (1, 3), (1, 5), (1, 9),
                             (None, 15), (3, 1), (5, 1), (9, 1), (None, None)):
            with self.subTest(needed=needed, used=used), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory)
                properties = b"".join(
                    struct.pack("<IIII", kind, 4, value, 0)
                    for kind, value in ((0xc0008002, needed), (0xc0010002, used))
                    if value is not None
                )
                note = struct.pack("<III4s", 4, len(properties), 5, b"GNU\0") + properties
                # ELF header, null section, SHT_NOTE section, then its contents.
                header = struct.pack("<16sHHIQQQIHHHHHH", b"\x7fELF\x02\x01\x01",
                                     3, 62, 1, 0, 0, 64, 0, 64, 0, 0, 64, 2, 0)
                section = struct.pack("<IIQQQQIIQQ", 0, 7, 2, 0, 192, len(note), 0, 0, 8, 0)
                (archive / "fixture.so").write_bytes(header + bytes(64) + section + note)
                target = next(t for t in targets if t["id"] == "x86_64-unknown-linux-gnu")
                if needed is not None and needed & 0xe:
                    with self.assertRaisesRegex(ValueError, "CPU baseline exceeds x86-64"):
                        module.verify(archive, target)
                else:
                    module.verify(archive, target)
                    report = json.loads((archive / "target-validation.json").read_text())
                    if used is not None:
                        self.assertIn("x86 ISA used:", report["files"][0]["notes"])

    def test_workflow_inventories_match(self):
        for target in targets:
            self.assertEqual(target["id"], target["target"])
        expected = sorted(t["target"] for t in targets if t["enabled"])
        for workflow in ("build.yml", "verify-public.yml"):
            actual = re.findall(r'^            target: (\S+)$', (root / ".github/workflows" / workflow).read_text(), re.M)
            self.assertEqual(sorted(actual), expected)
            self.assertEqual(len(actual), len(set(actual)))
            content = (root / ".github/workflows" / workflow).read_text()
            for target in (t for t in targets if t["enabled"]):
                start = content.index("          - id: " + target["id"] + "\n")
                end = content.index("\n\n", start)
                for field in ("os", "platform", "cflags", "qemu_cpu", "baseline_build"):
                    if field in target:
                        value = target[field]
                        if isinstance(value, bool):
                            value = str(value).lower()
                        self.assertIn(f'{field}: {value}', content[start:end])

    def test_reject_big_endian_mips_and_n32(self):
        target = next(t for t in targets if t["id"] == "mips64el-unknown-linux-gnuabi64")
        info = dict(bits=64, endian="little", machine=8, flags=0x80000007, interpreter=target["interpreter"])
        module.validate(info, target, True)
        for field, value in [("endian", "big"), ("bits", 32), ("flags", 0x20), ("flags", 0x80004000), ("flags", 0xa0000007), ("interpreter", "/wrong/loader")]:
            with self.assertRaises(ValueError):
                module.validate({**info, field: value}, target, True)

    def test_reject_hard_float_for_soft_float_target(self):
        target = next(t for t in targets if t["id"] == "arm-unknown-linux-gnueabi")
        with self.assertRaises(ValueError):
            module.validate(dict(bits=32, endian="little", machine=40, flags=0x5000400, interpreter=target["interpreter"]), target)


if __name__ == "__main__":
    unittest.main()
