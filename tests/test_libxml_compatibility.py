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


class LibxmlCompatibilityTests(unittest.TestCase):
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

if __name__ == "__main__":
    unittest.main()
