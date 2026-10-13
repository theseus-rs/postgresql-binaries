import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

# The declaration/definition layout used by PostgreSQL before the libxml2
# backport. Compile it against both callback APIs, including -Werror.
XML = """#define HAVE_LIBXML 1
#if HAVE_LIBXML
#define HAVE_XMLSTRUCTUREDERRORCONTEXT 1
#endif
typedef struct { int code; } xmlError;
typedef xmlError *xmlErrorPtr;
static void xml_errorHandler(void *data, xmlErrorPtr error);
static void xml_errorHandler(void *data, xmlErrorPtr error) { (void)data; (void)error; }
#if LIBXML_VERSION >= 21200
static void (*handler)(void *, const xmlError *) = xml_errorHandler;
#else
static void (*handler)(void *, xmlErrorPtr) = xml_errorHandler;
#endif
int main(void) { return handler == 0; }
"""


def source_fixture(path):
    xml = path / "src/backend/utils/adt/xml.c"
    xml.parent.mkdir(parents=True)
    xml.write_text(XML)
    xpath = path / "contrib/xml2/xpath.c"
    xpath.parent.mkdir(parents=True)
    xpath.write_text("void init(void) {\n\txmlLoadExtDtdDefaultValue = 1;\n}\n")
    return xml


class BaselineCompatibilityTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("cc"), "C compiler is required")
    def test_libxml_callback_compiles_with_old_and_new_api(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            xml = source_fixture(source)
            command = ["cc", "-Werror", "-fsyntax-only", "-DLIBXML_VERSION=21503", str(xml)]
            before = subprocess.run(command, capture_output=True)
            self.assertNotEqual(before.returncode, 0)
            subprocess.run([sys.executable, str(ROOT / "scripts/patch-postgresql-libxml2.py"), str(source)], check=True)
            patched = xml.read_bytes()
            subprocess.run(command, check=True)
            command[-2] = "-DLIBXML_VERSION=21100"
            subprocess.run(command, check=True)
            subprocess.run([sys.executable, str(ROOT / "scripts/patch-postgresql-libxml2.py"), str(source)], check=True)
            self.assertEqual(xml.read_bytes(), patched)
            self.assertNotIn("xmlLoadExtDtdDefaultValue", (source / "contrib/xml2/xpath.c").read_text())

    def test_baseline_patches_sources_before_make_and_pins_all_llvm_components(self):
        for version in ("14.0.0", "15.0.0", "16.0.0"):
            with self.subTest(version=version), tempfile.TemporaryDirectory() as directory:
                cache = Path(directory)
                (cache / "buildroot-2026.08").mkdir()
                (cache / "buildroot-2026.08.tar.xz").touch()
                output = cache / ("i586-unknown-linux-musl" + ("-llvm-16.0.6" if version == "16.0.0" else ""))
                source = output / f"postgresql-source-{version}"
                xml = source_fixture(source)
                bin_dir = cache / "bin"
                bin_dir.mkdir()
                # Stop at the first make invocation. This checks the real build
                # entrypoint without downloading or compiling an entire sysroot.
                (bin_dir / "sha256sum").write_text("#!/bin/sh\ncat >/dev/null\n")
                (bin_dir / "make").write_text(
                    f"#!{sys.executable}\nimport json, os, pathlib, sys\n"
                    "assert 'PgXmlErrorPtr' in pathlib.Path(os.environ['XML_FIXTURE']).read_text()\n"
                    "pathlib.Path(os.environ['MAKE_ARGS']).write_text(json.dumps(sys.argv[1:]))\n"
                    "sys.exit(77)\n")
                for tool in bin_dir.iterdir():
                    tool.chmod(0o755)
                args_file = cache / "make-args.json"
                env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                           BUILDROOT_CACHE=str(cache), XML_FIXTURE=str(xml), MAKE_ARGS=str(args_file))
                result = subprocess.run(
                    ["bash", str(ROOT / "scripts/build-baseline-linux.sh"), version,
                     "i586-unknown-linux-musl", "linux/386"], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
                args = json.loads(args_file.read_text())
                if version == "16.0.0":
                    self.assertIn("LLVM_PROJECT_VERSION_MAJOR=16", args)
                    self.assertIn("LLVM_PROJECT_VERSION=16.0.6", args)
                    for package in ("LLVM", "HOST_LLVM", "CLANG", "HOST_CLANG", "HOST_LLVM_CMAKE"):
                        self.assertIn(f"{package}_HASH_FILES={ROOT}/buildroot/patches/llvm-project/16.0.6/llvm-project.hash", args)
                    self.assertIn("BR2_PACKAGE_LLVM=y", (output / "defconfig").read_text())
                else:
                    self.assertFalse(any(arg.startswith("LLVM_PROJECT_VERSION=") for arg in args))
                    self.assertNotIn("BR2_PACKAGE_LLVM=y", (output / "defconfig").read_text())


if __name__ == "__main__":
    unittest.main()
