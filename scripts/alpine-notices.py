#!/usr/bin/env python3
"""Collect notices from the exact Alpine package recipe's verified sources."""

import hashlib
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile


def installed_packages():
    packages = {}
    for paragraph in Path("/lib/apk/db/installed").read_text().split("\n\n"):
        fields = {}
        for line in paragraph.splitlines():
            if line[:2] in ("P:", "V:", "o:", "c:", "L:"):
                fields[line[0]] = line[2:]
        if "P" in fields:
            packages[fields["P"] + "-" + fields["V"]] = fields
    return packages


def collect(package, destination):
    info = installed_packages()[package]
    if not re.fullmatch(r"[0-9a-f]{40}", info["c"]):
        raise ValueError("Missing immutable Alpine source recipe revision")
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        temporary = Path(directory)
        recipe = temporary / "APKBUILD"
        # Alpine's official GitHub mirror is addressed by the installed package's
        # source commit, not a moving branch. HTTPS uses the installed CA store.
        for repository in ("main", "community"):
            url = f"https://raw.githubusercontent.com/alpinelinux/aports/{info['c']}/{repository}/{info['o']}/APKBUILD"
            try:
                urllib.request.urlretrieve(url, recipe)
                break
            except urllib.error.HTTPError as error:
                if error.code != 404:
                    raise
        else:
            raise ValueError("Cannot find exact Alpine source recipe")
        # Evaluate the distribution's pinned recipe metadata, without invoking
        # prepare/build/package. Source archives must also match its SHA-512s.
        subprocess.run(["bash", "-c", 'source "$1"; printf "%s\\n" "$source" > "$2/sources"; printf "%s\\n" "$sha512sums" > "$2/checksums"',
                        "bash", str(recipe), str(temporary)], check=True, cwd=temporary)
        checksums = {}
        for line in (temporary / "checksums").read_text().splitlines():
            fields = line.split()
            if len(fields) == 2 and re.fullmatch(r"[0-9a-f]{128}", fields[0]):
                checksums[fields[1]] = fields[0]
        count = 0
        inputs = []
        for value in (temporary / "sources").read_text().split():
            source_url = value.split("::", 1)[-1]
            if not source_url.startswith(("http://", "https://")):
                continue  # Local aports patches are not source archives.
            name = value.split("::", 1)[0] if "::" in value else source_url.rsplit("/", 1)[-1]
            if name not in checksums or "/" in name:
                raise ValueError(f"Unverified Alpine source: {name}")
            archive = temporary / name
            mirror = f"https://distfiles.alpinelinux.org/distfiles/v3.19/{name}"
            urllib.request.urlretrieve(mirror, archive)
            digest = hashlib.file_digest(archive.open("rb"), "sha512").hexdigest()
            if digest != checksums[name]:
                raise ValueError(f"Alpine source digest mismatch: {name}")
            inputs.append({"url": mirror, "sha512": digest, "recipe_url": url})
            def save(member_name, data):
                nonlocal count
                path = PurePosixPath(member_name)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError("Unsafe notice path")
                output = destination / name / path
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(data)
                count += 1
            def notice(member_name):
                return PurePosixPath(member_name).name.upper().startswith(("COPYING", "COPYRIGHT", "LICENSE", "NOTICE", "AUTHORS"))
            if tarfile.is_tarfile(archive):
                with tarfile.open(archive) as tar:
                    for entry in tar:
                        if entry.isfile() and notice(entry.name):
                            save(entry.name, tar.extractfile(entry).read())
            elif zipfile.is_zipfile(archive):
                with zipfile.ZipFile(archive) as z:
                    for entry in z.infolist():
                        if not entry.is_dir() and notice(entry.filename):
                            save(entry.filename, z.read(entry))
            archive.unlink()
        if not count:
            raise ValueError(f"No upstream notices found for {package}")
        return {"package_version": info["V"], "license": info["L"], "notice_sources": inputs}
