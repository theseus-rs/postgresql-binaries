import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("checksum", Path(__file__).parents[1] / "scripts/verify-checksum.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ChecksumTests(unittest.TestCase):
    def test_valid_and_tampered_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            asset = Path(directory) / "archive.tar.gz"
            checksum = Path(directory) / "archive.tar.gz.sha256"
            asset.write_bytes(b"")
            checksum.write_text("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  archive.tar.gz\n")
            module.verify(asset, checksum)
            asset.write_bytes(b"tampered")
            with self.assertRaises(ValueError):
                module.verify(asset, checksum)

    def test_wrong_filename_and_duplicate_record(self):
        with tempfile.TemporaryDirectory() as directory:
            asset = Path(directory) / "archive.tar.gz"
            checksum = Path(directory) / "checksum"
            for record in ["0" * 64 + "  other.tar.gz\n", "0" * 64 + "  archive.tar.gz\nextra\n"]:
                checksum.write_text(record)
                with self.assertRaises(ValueError):
                    module.verify(asset, checksum)


if __name__ == "__main__":
    unittest.main()
