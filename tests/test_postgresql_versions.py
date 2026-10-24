import datetime
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("matrix", ROOT / "scripts/build-matrix.py")
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)


class PostgreSQLVersionTests(unittest.TestCase):
    def test_ci_covers_every_supported_major_once(self):
        plan = json.loads(subprocess.check_output(
            ["python3", str(ROOT / "scripts/build-matrix.py")], text=True))
        versions = [*plan["previous"], plan["latest"]]
        self.assertEqual(versions, matrix.policy("current").splitlines())
        self.assertEqual([v.split(".")[0] for v in versions], ["14", "15", "16", "17", "18"])
        self.assertEqual(plan["oldest"], [f"{v.split('.')[0]}.0.0" for v in versions
                                         if f"{v.split('.')[0]}.0.0" not in versions])

    def test_new_major_does_not_duplicate_oldest_release_artifacts(self):
        responses = {"current": "17.11.0\n18.0.0", "oldest": "17.0.0\n18.0.0"}
        with patch.object(matrix, "policy", side_effect=lambda name: responses[name]):
            self.assertEqual(matrix.ci_versions(), dict(latest="18.0.0", previous=["17.11.0"],
                                                       oldest=["17.0.0"]))

    def test_matrix_covers_all_supported_targets(self):
        targets = json.loads((ROOT / "targets.json").read_text())
        enabled = {t["target"] for t in targets if t["enabled"]}
        for version in matrix.policy("current").splitlines():
            with self.subTest(version=version):
                entries = matrix.build_matrix(version)["include"]
                expected = enabled.copy()
                if int(version.split(".")[0]) < 16:
                    expected.remove("aarch64-pc-windows-msvc")
                self.assertEqual({t["id"] for t in entries}, expected)
                self.assertEqual(len(entries), len(expected))
                for entry in entries:
                    self.assertEqual(entry["id"], entry["target"])
                    if "windows" in entry["target"]:
                        self.assertIn("vcpkg_triplet", entry)
                        self.assertIsInstance(entry["pe_machine"], str)

    def test_old_releases_and_packaging_revisions_remain_accepted(self):
        for version in ("14.0.0", "15.0.0", "16.0.0", "17.0.0", "18.0.12"):
            with self.subTest(version=version):
                entries = matrix.build_matrix(version, "x86_64-unknown-linux-musl")["include"]
                self.assertEqual(len(entries), 1)
                self.assertEqual(entries[0]["target"], "x86_64-unknown-linux-musl")

    def test_eol_dates_cover_every_supported_major_and_packaging_revision(self):
        for version in matrix.policy("current").splitlines():
            with self.subTest(version=version):
                eol = datetime.date.fromisoformat(matrix.policy("eol", version))
                self.assertEqual(matrix.policy("eol", f"{version.split('.')[0]}.0.12"), eol.isoformat())
        self.assertEqual(matrix.policy("eol", "14.24.0"), "2026-11-12")
        self.assertEqual(matrix.policy("eol", "18.6.0"), "2030-11-14")

    def test_reject_invalid_versions_and_unsupported_targets(self):
        for version in ("13.23.0", "19.0.0", "16.0", "16.0.0-extra", "16.0.0\n18.6.0", "", "016.0.0"):
            with self.subTest(version=version), self.assertRaises(subprocess.CalledProcessError):
                matrix.policy("validate", version)
        for version, target in (("14.0.0", "aarch64-pc-windows-msvc"), ("18.6.0", "unknown"),
                                ("18.6.0", "i586-unknown-linux-musl"), ("18.6.0", "i686-unknown-linux-musl")):
            with self.subTest(target=target), self.assertRaises(ValueError):
                matrix.build_matrix(version, target)
        for version in ("13.23.0", "18.6", "18.6.0-extra"):
            with self.subTest(version=version), self.assertRaises(subprocess.CalledProcessError):
                matrix.policy("eol", version)

    def test_llvm_backport_only_applies_to_postgresql_16_0(self):
        for version in ("16.0.0", "16.0.12"):
            self.assertEqual(matrix.policy("source-patches", version).splitlines(),
                             ["postgresql-16.0-llvm16.patch", "postgresql-16-macos-strchrnul.patch"])
        for version in ("14.0.0", "15.0.0", "16.1.0", "16.15.0", "17.0.0", "18.0.0"):
            self.assertNotIn("postgresql-16.0-llvm16.patch",
                             matrix.policy("source-patches", version).splitlines())

    def test_macos_backport_stops_at_the_upstream_fix(self):
        for major, first_fixed in ((14, 18), (15, 13), (16, 9), (17, 5)):
            expected = f"postgresql-{major}-macos-strchrnul.patch"
            for minor in range(first_fixed + 2):
                for revision in (0, 12):
                    version = f"{major}.{minor}.{revision}"
                    with self.subTest(version=version):
                        patches = matrix.policy("source-patches", version).splitlines()
                        self.assertEqual(expected in patches, minor < first_fixed)
        for version in ("18.0.0", "18.6.12"):
            self.assertEqual(matrix.policy("source-patches", version), "")


if __name__ == "__main__":
    unittest.main()
