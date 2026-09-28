#!/usr/bin/env python3
"""Report upstream updates/EOL without changing refs or publishing binaries."""

import datetime
import json
from pathlib import Path
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET


def compare(feed, supported, today):
    latest = {}
    for item in ET.fromstring(feed).findall("./channel/item"):
        version = item.findtext("title", "").strip()
        if re.fullmatch(r"[0-9]+\.[0-9]+", version) and "unsupported" not in item.findtext("description", "").lower():
            latest[int(version.split(".")[0])] = version
    if not latest:
        raise ValueError("Upstream feed contains no supported stable versions")
    findings = []
    known = {row["major"] for row in supported}
    for row in supported:
        if today >= datetime.date.fromisoformat(row["eol"]):
            findings.append(f"PostgreSQL {row['major']} reached EOL; retire active support")
        elif latest.get(row["major"]) != row["version"]:
            findings.append(f"PostgreSQL {row['major']}: recorded {row['version']}, upstream {latest.get(row['major'], 'missing')}")
    for major in latest.keys() - known:
        findings.append(f"New supported upstream major: {latest[major]}; review before adding targets")
    return findings


if __name__ == "__main__":
    if len(sys.argv) > 1:
        feed = Path(sys.argv[1]).read_bytes()
    else:
        with urllib.request.urlopen("https://www.postgresql.org/versions.rss", timeout=60) as response:
            feed = response.read()
    supported = json.loads((Path(__file__).parents[1] / "supported-versions.json").read_text())
    findings = compare(feed, supported, datetime.date.today())
    print("\n".join(findings) if findings else "Tracked stable PostgreSQL versions are current")
    sys.exit(bool(findings))
