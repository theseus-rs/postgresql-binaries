import datetime
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("upstream", Path(__file__).parents[1] / "scripts/check-upstream.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UpstreamTests(unittest.TestCase):
    def test_update_and_eol_are_reported(self):
        feed = '<rss><channel><item><title>18.6</title><description>stable</description></item></channel></rss>'
        supported = [{"major": 18, "version": "18.5", "eol": "2030-11-14"}]
        self.assertIn("upstream 18.6", module.compare(feed, supported, datetime.date(2026, 9, 27))[0])
        self.assertIn("reached EOL", module.compare(feed, supported, datetime.date(2031, 1, 1))[0])

    def test_invalid_feed_fails_closed(self):
        with self.assertRaises(ValueError):
            module.compare("<rss><channel/></rss>", [], datetime.date.today())


if __name__ == "__main__":
    unittest.main()
