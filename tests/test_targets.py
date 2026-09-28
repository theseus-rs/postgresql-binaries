import importlib.util
import json
from pathlib import Path
import re
import unittest

root = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location("target", root / "scripts/verify-target.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
targets = json.loads((root / "targets.json").read_text())


class TargetTests(unittest.TestCase):
    def test_workflow_inventories_match(self):
        expected = sorted(t["target"] for t in targets if t["enabled"])
        for workflow in ("build.yml", "verify-public.yml"):
            actual = re.findall(r'^            target: "([^"]+)"$', (root / ".github/workflows" / workflow).read_text(), re.M)
            self.assertEqual(sorted(actual), expected)
            self.assertEqual(len(actual), len(set(actual)))
            content = (root / ".github/workflows" / workflow).read_text()
            for target in (t for t in targets if t["enabled"]):
                start = content.index("          - id: " + target["id"] + "\n")
                end = content.index("\n\n", start)
                for field in ("os", "platform", "cflags", "qemu_cpu"):
                    if field in target:
                        self.assertIn(f'{field}: "{target[field]}"', content[start:end])

    def test_reject_big_endian_mips_and_n32(self):
        target = next(t for t in targets if t["id"] == "linux-mips64le")
        info = dict(bits=64, endian="little", machine=8, flags=0x80000007, interpreter=target["interpreter"])
        module.validate(info, target, True)
        for field, value in [("endian", "big"), ("bits", 32), ("flags", 0x20), ("flags", 0x80004000), ("flags", 0xa0000007), ("interpreter", "/wrong/loader")]:
            with self.assertRaises(ValueError):
                module.validate({**info, field: value}, target, True)

    def test_reject_hard_float_for_soft_float_target(self):
        target = next(t for t in targets if t["id"] == "linux-arm")
        with self.assertRaises(ValueError):
            module.validate(dict(bits=32, endian="little", machine=40, flags=0x5000400, interpreter=target["interpreter"]), target)


if __name__ == "__main__":
    unittest.main()
