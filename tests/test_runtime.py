import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("runtime", Path(__file__).parents[1] / "scripts/bundle-runtime.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RuntimeTests(unittest.TestCase):
    def test_only_os_abi_libraries_are_exempt(self):
        for name in ["libc.so.6", "libm.so.6", "libc.musl-x86_64.so.1", "ld-linux-x86-64.so.2"]:
            self.assertTrue(module.system_library(name), name)
        for name in ["libxml2.so.2", "libicuuc.so.72", "libssl.so.3", "libstdc++.so.6", "libpython3.11.so.1.0", "libcrypto.so.3"]:
            self.assertFalse(module.system_library(name), name)

    def test_homebrew_is_not_a_system_library(self):
        self.assertFalse(module.system_library("/opt/homebrew/opt/openssl/lib/libssl.3.dylib", True))
        self.assertTrue(module.system_library("/usr/lib/libSystem.B.dylib", True))


if __name__ == "__main__":
    unittest.main()
