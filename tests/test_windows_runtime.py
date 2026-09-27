import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("windows", Path(__file__).parents[1] / "scripts/windows-runtime.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def pe_with_import(name):
    data = bytearray(1024)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3c, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<H", data, 0x86, 1)
    struct.pack_into("<H", data, 0x94, 240)
    struct.pack_into("<H", data, 0x98, 0x20b)
    struct.pack_into("<I", data, 0x98 + 120, 0x1000)
    struct.pack_into("<IIII", data, 0x98 + 240 + 8, 512, 0x1000, 512, 512)
    struct.pack_into("<I", data, 512 + 12, 0x1100)
    encoded = name.encode() + b"\0"
    data[768:768 + len(encoded)] = encoded
    return bytes(data)


class WindowsRuntimeTests(unittest.TestCase):
    def test_python_abi_from_import_table(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "lib").mkdir()
            (root / "lib/plpython3.dll").write_bytes(pe_with_import("PYTHON313.dll"))
            self.assertEqual(module.python_version(root), "3.13")
            (root / "lib/other_plpython.dll").write_bytes(pe_with_import("python314.dll"))
            with self.assertRaises(ValueError):
                module.python_version(root)

    def test_reject_import_path(self):
        with self.assertRaises(ValueError):
            module.imports(pe_with_import("../python313.dll"))


if __name__ == "__main__":
    unittest.main()
