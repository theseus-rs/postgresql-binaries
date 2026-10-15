import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


script = Path(__file__).parents[1] / "scripts/build-metadata.py"


class BuildMetadataTests(unittest.TestCase):
    def generate(self, target, baseline=False, revision="a" * 40):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "include").mkdir()
            (root / "include/pg_config.h").write_text("#define USE_ICU 1\n")
            (root / "lib/postgresql").mkdir(parents=True)
            (root / "lib/postgresql/plpython3.dll").touch()
            (root / "share/postgresql/timezone").mkdir(parents=True)
            (root / "share/postgresql/timezone/UTC").touch()
            source = {"commit": "b" * 40, "url": "https://example.test/postgresql.git"}
            (root / "source-input.json").write_text(json.dumps(source))
            runtime = {"bundled": [], "dependency_builder": "Buildroot 2026.08"}
            (root / "runtime-dependencies.json").write_text(json.dumps(runtime))
            if baseline:
                (root / "buildroot.config").write_text("BR2_x86_i586=y\n")
            helper = root / "config.py"
            helper.write_text("import sys\nprint({'--configure': '--with-icu', "
                              "'--cc': 'target-gcc', '--cflags': '-march=i586', "
                              "'--ldflags': '-L/target', '--version': 'target-gcc 15'}[sys.argv[1]])\n")
            environment = {**os.environ, "BUILD_REVISION": revision,
                           "PG_CONFIG_COMMAND": json.dumps([sys.executable, str(helper)]),
                           "CC": f"{sys.executable} {helper}"}
            subprocess.run([sys.executable, str(script), str(root), "18.6.0", target],
                           env=environment, check=True, capture_output=True)
            return json.loads((root / "build-manifest.json").read_text())

    def test_windows_source_build_identity(self):
        build = self.generate("aarch64-pc-windows-msvc")
        self.assertEqual(build["build_mode"], "source")
        self.assertNotIn("verification_limit", build["runtime"])
        self.assertTrue(build["features"]["icu"])
        self.assertTrue(build["features"]["python"])
        self.assertTrue(build["features"]["bundled_timezone"])

    def test_baseline_uses_target_configuration(self):
        build = self.generate("i586-unknown-linux-gnu", baseline=True)
        self.assertEqual(build["configure_flags"], "--with-icu")
        self.assertEqual(build["toolchain"]["compiler_version"], "target-gcc 15")
        self.assertEqual(build["toolchain"]["buildroot_config"], "BR2_x86_i586=y\n")
        self.assertNotIn("installed_packages", build["toolchain"])

    def test_rejects_invalid_revision(self):
        with self.assertRaises(subprocess.CalledProcessError) as error:
            self.generate("aarch64-pc-windows-msvc", revision="main")
        self.assertIn(b"BUILD_REVISION", error.exception.stderr)
