import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("manifest", Path(__file__).parents[1] / "scripts/archive-manifest.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ManifestTests(unittest.TestCase):
    def test_round_trip_and_false_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            asset = Path(directory) / "postgresql-18.6.0-test.tar.gz"
            build = {"version": "18.6.0", "target": "test", "source": {"url": "https://example.test/source"}, "runtime": {"bundled": []}}
            with tarfile.open(asset, "w:gz") as tar:
                data = json.dumps(build).encode()
                entry = tarfile.TarInfo("postgresql-18.6.0-test/build-manifest.json")
                entry.size = len(data)
                tar.addfile(entry, io.BytesIO(data))
                link = tarfile.TarInfo("postgresql-18.6.0-test/timezone-alias")
                link.type = tarfile.LNKTYPE
                link.linkname = entry.name
                tar.addfile(link)
            module.generate(asset)
            module.verify(asset)
            sbom_path = Path(str(asset) + ".spdx.json")
            sbom = json.loads(sbom_path.read_text())
            sbom["packages"][0]["versionInfo"] = "0.0"
            sbom_path.write_text(json.dumps(sbom))
            with self.assertRaises(ValueError):
                module.verify(asset)
            module.generate(asset)
            manifest_path = Path(str(asset) + ".manifest.json")
            manifest = json.loads(manifest_path.read_text())
            manifest["files"] = {}
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                module.verify(asset)

    def test_reject_escaping_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            asset = Path(directory) / "unsafe.tar.gz"
            with tarfile.open(asset, "w:gz") as tar:
                entry = tarfile.TarInfo("root/link")
                entry.type = tarfile.SYMTYPE
                entry.linkname = "../../outside"
                tar.addfile(entry)
            with self.assertRaises(ValueError):
                module.inventory(asset)


if __name__ == "__main__":
    unittest.main()
