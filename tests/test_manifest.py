import hashlib
import importlib.util
import io
import itertools
import json
from pathlib import Path
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock
import zipfile

script = Path(__file__).parents[1] / "scripts/archive-manifest.py"
spec = importlib.util.spec_from_file_location("manifest", script)
module = importlib.util.module_from_spec(spec)
with mock.patch.object(sys, "path", [str(script.parent), *sys.path]):
    spec.loader.exec_module(module)


class ManifestTests(unittest.TestCase):
    def write_archive(self, directory, links=(), extension="tar.gz", files=None):
        root = "postgresql-18.6.0-test"
        asset = Path(directory) / f"{root}.{extension}"
        build = {"version": "18.6.0", "target": "test", "source": {"url": "https://example.test/source"},
                 "runtime": {"bundled": []}}
        contents = {"build-manifest.json": json.dumps(build).encode(), **(files or {})}
        records = {}
        if extension == "tar.gz":
            with tarfile.open(asset, "w:gz") as archive:
                for name, data in contents.items():
                    entry = tarfile.TarInfo(f"{root}/{name}")
                    entry.size = len(data)
                    archive.addfile(entry, io.BytesIO(data))
                for name, target in links:
                    entry = tarfile.TarInfo(f"{root}/{name}")
                    entry.type = tarfile.SYMTYPE
                    entry.linkname = target
                    archive.addfile(entry)
                    records[entry.name] = {"symlink": target}
        else:
            with zipfile.ZipFile(asset, "w") as archive:
                for name, data in contents.items():
                    archive.writestr(f"{root}/{name}", data)
                for name, target in links:
                    entry = zipfile.ZipInfo(f"{root}/{name}")
                    entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(entry, target)
                    contents[name] = target.encode()
        records.update({f"{root}/{name}": {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
                        for name, data in contents.items()})
        return asset, records

    def assert_links_rejected(self, links, error, files=None):
        for extension in ("tar.gz", "zip"):
            with self.subTest(extension=extension), tempfile.TemporaryDirectory() as directory:
                # Start with valid sidecars, then describe the unsafe fixture
                # accurately. Verification must fail on links, not stale hashes,
                # a missing build manifest, or an inconsistent inventory/SBOM.
                asset, _ = self.write_archive(directory, extension=extension)
                module.generate(asset)
                asset, records = self.write_archive(directory, links, extension, files)
                manifest_path = Path(str(asset) + ".manifest.json")
                manifest = json.loads(manifest_path.read_text())
                manifest.update(sha256=hashlib.sha256(asset.read_bytes()).hexdigest(), files=records)
                manifest_path.write_text(json.dumps(manifest))
                sbom_path = Path(str(asset) + ".spdx.json")
                sbom = json.loads(sbom_path.read_text())
                template = sbom["files"][0]
                sbom["files"] = [dict(template, SPDXID=f"SPDXRef-File-{i}", fileName=name,
                                      checksums=[{"algorithm": "SHA256", "checksumValue": record["sha256"]}])
                                 for i, (name, record) in enumerate(sorted(records.items()))
                                 if "sha256" in record]
                sbom_path.write_text(json.dumps(sbom))
                with self.assertRaisesRegex(ValueError, error):
                    module.inventory(asset)
                for command in ("generate", "verify"):
                    with self.subTest(command=command):
                        result = subprocess.run([sys.executable, str(script), command, str(asset)],
                                                capture_output=True, text=True)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertRegex(result.stderr, error)

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
        self.assert_links_rejected([("link", "../../outside")], "Link escapes the archive root")

    def test_reject_escaping_symlink_chain(self):
        # Every target is lexically contained. Following a before '..' escapes
        # the installation via c, then the extraction directory via b.
        for links in itertools.permutations([("a", "."), ("c", "a/.."), ("b", "c/../outside")]):
            with self.subTest(links=links):
                self.assert_links_rejected(links, "Link escapes the archive root")

    def test_reject_symlink_cycles(self):
        for links in ([('a', 'a')], [('a', 'b'), ('b', 'a')]):
            with self.subTest(links=links):
                self.assert_links_rejected(links, "Cyclic or excessively deep archive link")

    def test_reject_excessively_deep_symlink_chain(self):
        links = [(f"a{i}", f"a{i + 1}") for i in range(40)] + [("a40", "build-manifest.json")]
        self.assert_links_rejected(links, "Cyclic or excessively deep archive link")

    def test_reject_member_under_symlink(self):
        self.assert_links_rejected([("alias", ".")], "Archive member has a non-directory parent",
                                   files={"alias/file": b"payload"})

    def test_accept_contained_symlink_chains(self):
        links = [("a", "."), ("b", "a/a/lib/file"),
                 ("lib/chain", "alias/../file"), ("lib/alias", "nested"),
                 ("lib/up", ".."), ("lib/through-up", "up/lib/file"),
                 ("dangling", "lib/missing")]
        for extension, ordered in itertools.product(("tar.gz", "zip"), (links, list(reversed(links)))):
            with self.subTest(extension=extension, links=ordered), tempfile.TemporaryDirectory() as directory:
                asset, records = self.write_archive(directory, ordered, extension,
                                                    files={"lib/file": b"payload", "lib/nested/file": b"nested"})
                module.generate(asset)
                module.verify(asset)
                self.assertEqual(module.inventory(asset)[0], records)


if __name__ == "__main__":
    unittest.main()
