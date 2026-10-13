#!/usr/bin/env python3
"""Select CI builds using the shared version policy and target inventory."""

import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def policy(*args):
    return subprocess.check_output(
        ["sh", str(ROOT / "scripts/postgresql-versions.sh"), *args], text=True
    ).strip()


def build_matrix(version, target=None):
    policy("validate", version)
    targets = json.loads((ROOT / "targets.json").read_text())
    builds = [entry for entry in targets if entry["enabled"]
              and (target is None or entry["target"] == target)
              and policy("supports-target", version, entry["target"]) == "true"]
    if not builds:
        raise ValueError(f"No supported targets for PostgreSQL {version}: {target}")
    return {"include": builds}


def ci_versions():
    versions = policy("current").splitlines()
    # A newly supported major may still be at .0. Its full target matrix
    # already covers the oldest release; do not upload the same artifact twice.
    return dict(latest=versions[-1], previous=versions[:-1],
                oldest=[v for v in policy("oldest").splitlines() if v not in versions])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version")
    parser.add_argument("--target")
    args = parser.parse_args()
    if args.version:
        result = build_matrix(args.version, args.target)
    else:
        result = ci_versions()
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    main()
