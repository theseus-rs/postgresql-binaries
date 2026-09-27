import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("relocate", Path(__file__).parents[1] / "scripts/relocate-plpython.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PythonPatchTests(unittest.TestCase):
    def test_patch_records_inputs_and_rejects_reapplication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "src/pl/plpython/plpy_main.c"
            source.parent.mkdir(parents=True)
            source.write_text("\tPy_Initialize();\n")
            (root / "source-input.json").write_text('{"version": "18.6"}')
            module.patch(root)
            record = json.loads((root / "source-input.json").read_text())["packaging_patches"][0]
            self.assertNotEqual(record["before_sha256"], record["after_sha256"])
            with self.assertRaises(ValueError):
                module.patch(root)


if __name__ == "__main__":
    unittest.main()
