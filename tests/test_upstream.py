import datetime
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("upstream", Path(__file__).parents[1] / "scripts/check-upstream.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UpstreamTests(unittest.TestCase):
    def test_update_and_eol_are_reported(self):
        feed = '<rss><channel><item><title>18.6</title><description>stable</description></item></channel></rss>'
        supported = [{"major": 18, "version": "18.5", "eol": "2030-11-14"}]
        self.assertIn("upstream 18.6", module.compare(feed, supported, datetime.date(2026, 9, 27))[0])
        self.assertIn("reached EOL", module.compare(feed, supported, datetime.date(2030, 11, 14))[0])
        self.assertIn("reached EOL", module.compare(feed, supported, datetime.date(2031, 1, 1))[0])

    def test_cli_reads_shell_policy_outside_repository_and_ignores_packaging_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            checker = scripts / "check-upstream.py"
            shutil.copyfile(module.__file__, checker)
            policy = scripts / "postgresql-versions.sh"
            policy.write_text("""#!/bin/sh
case "$1" in
    current) echo 18.6.12 ;;
    eol) echo 2099-11-14 ;;
    *) exit 1 ;;
esac
""")
            feed = root / "feed.xml"
            feed.write_text('<rss><channel><item><title>18.6</title><description>stable</description></item></channel></rss>')
            result = subprocess.run([sys.executable, str(checker), str(feed)], cwd=root,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Tracked stable PostgreSQL versions are current", result.stdout)

            policy.write_text(policy.read_text().replace("18.6.12", "18.5.12"))
            result = subprocess.run([sys.executable, str(checker), str(feed)], cwd=root,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("recorded 18.5, upstream 18.6", result.stdout)

    def test_invalid_feed_fails_closed(self):
        with self.assertRaises(ValueError):
            module.compare("<rss><channel/></rss>", [], datetime.date.today())


if __name__ == "__main__":
    unittest.main()
