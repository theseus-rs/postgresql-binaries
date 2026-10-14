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
                entries = matrix.build_matrix(version, "i586-unknown-linux-musl")["include"]
                self.assertEqual(len(entries), 1)
                self.assertTrue(entries[0]["baseline_build"])

    def test_reject_invalid_versions_and_unsupported_targets(self):
        for version in ("13.23.0", "19.0.0", "16.0", "16.0.0-extra", "16.0.0\n18.6.0", "", "016.0.0"):
            with self.subTest(version=version), self.assertRaises(subprocess.CalledProcessError):
                matrix.policy("validate", version)
        for version, target in (("14.0.0", "aarch64-pc-windows-msvc"), ("18.6.0", "unknown")):
            with self.subTest(target=target), self.assertRaises(ValueError):
                matrix.build_matrix(version, target)

    def test_jit_uses_llvm_compatible_with_oldest_sources(self):
        for major in (14, 15):
            self.assertEqual(matrix.policy("baseline-llvm", f"{major}.0.0"), "")
        for version in ("16.0.0", "16.15.0", "17.0.0", "17.11.0", "18.0.0", "18.6.0"):
            self.assertEqual(matrix.policy("baseline-llvm", version), "16.0.6")

    def test_llvm_backport_only_applies_to_postgresql_16_0(self):
        for version in ("16.0.0", "16.0.12"):
            self.assertEqual(matrix.policy("source-patches", version), "postgresql-16.0-llvm16.patch")
        for version in ("14.0.0", "15.0.0", "16.1.0", "16.15.0", "17.0.0", "18.0.0"):
            self.assertEqual(matrix.policy("source-patches", version), "")


if __name__ == "__main__":
    unittest.main()
