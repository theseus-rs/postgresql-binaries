#!/usr/bin/env python3
"""Emit/verify an archive inventory and SPDX SBOM without extracting it."""

import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inventory(path):
    records, contents = {}, {}
    if path.name.endswith(".tar.gz"):
        with tarfile.open(path) as archive:
            for entry in archive:
                if entry.isdir():
                    continue
                name = entry.name
                if name in records:
                    raise ValueError(f"Duplicate archive member: {name}")
                if entry.issym():
                    records[name] = {"symlink": entry.linkname}
                elif entry.islnk():
                    target = PurePosixPath(entry.linkname)
                    if target.is_absolute() or ".." in target.parts or "\\" in entry.linkname:
                        raise ValueError("Unsafe archive hardlink")
                    data = archive.extractfile(entry).read()
                    records[name] = {"hardlink": entry.linkname, "sha256": sha(data), "size": len(data)}
                elif entry.isfile():
                    data = archive.extractfile(entry).read()
                    records[name] = {"sha256": sha(data), "size": len(data)}
                    if name.endswith("/build-manifest.json"):
                        contents[name] = data
                else:
                    raise ValueError(f"Unsupported archive member: {name}")
    elif path.suffix == ".zip":
        with zipfile.ZipFile(path) as archive:
            for entry in archive.infolist():
                if entry.is_dir():
                    continue
                if entry.filename in records:
                    raise ValueError("Duplicate ZIP member")
                data = archive.read(entry)
                records[entry.filename] = {"sha256": sha(data), "size": len(data)}
                if entry.filename.endswith("/build-manifest.json"):
                    contents[entry.filename] = data
    else:
        raise ValueError("Unsupported archive format")
    for name, record in records.items():
        path_parts = PurePosixPath(name)
        if path_parts.is_absolute() or ".." in path_parts.parts or "\\" in name:
            raise ValueError("Unsafe archive member")
        if "hardlink" in record and (record["hardlink"] not in records or
                                      PurePosixPath(record["hardlink"]).parts[0] != path_parts.parts[0]):
            raise ValueError("Hardlink escapes installation")
        if "symlink" in record:
            link = PurePosixPath(record["symlink"])
            parts = list(path_parts.parent.parts)
            if link.is_absolute():
                raise ValueError("Absolute archive symlink")
            for part in link.parts:
                if part == "..":
                    if len(parts) <= 1:
                        raise ValueError("Symlink escapes installation")
                    parts.pop()
                elif part != ".":
                    parts.append(part)
    if len(contents) != 1:
        raise ValueError("Expected exactly one build manifest")
    return records, json.loads(next(iter(contents.values())))


def generate(asset):
    files, build = inventory(asset)
    prefix = f"postgresql-{build['version']}-{build['target']}/"
    if any(not name.startswith(prefix) for name in files):
        raise ValueError("Archive root does not match its build manifest")
    if asset.name not in (prefix[:-1] + ".tar.gz", prefix[:-1] + ".zip"):
        raise ValueError("Asset filename does not match the embedded version/target")
    manifest = {"schema_version": 1, "archive": asset.name,
                "sha256": file_sha(asset),
                "build": build, "files": files}
    Path(str(asset) + ".manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    packages = [{"SPDXID": "SPDXRef-PostgreSQL", "name": "PostgreSQL", "versionInfo": build["version"].rsplit(".", 1)[0],
                 "downloadLocation": build["source"]["url"], "filesAnalyzed": False,
                 "licenseConcluded": "NOASSERTION", "licenseDeclared": "PostgreSQL", "copyrightText": "NOASSERTION"}]
    relations = [{"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": "SPDXRef-PostgreSQL"}]
    for i, item in enumerate(build["runtime"].get("bundled", [])):
        identifier = f"SPDXRef-Dependency-{i}"
        packages.append({"SPDXID": identifier, "name": item.get("package", Path(item["file"]).name),
                         "versionInfo": item.get("package_version", "NOASSERTION"),
                         "downloadLocation": "NOASSERTION", "filesAnalyzed": False,
                         "licenseConcluded": "NOASSERTION", "licenseDeclared": "NOASSERTION", "copyrightText": "NOASSERTION"})
        relations.append({"spdxElementId": "SPDXRef-PostgreSQL", "relationshipType": "DEPENDS_ON", "relatedSpdxElement": identifier})
    sbom = {"spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT",
            "name": asset.name, "documentNamespace": f"https://github.com/theseus-rs/postgresql-binaries/sbom/{manifest['sha256']}",
            "creationInfo": {"created": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                             "creators": ["Tool: postgresql-binaries-archive-manifest"]},
            "packages": packages, "relationships": relations,
            "files": [{"SPDXID": f"SPDXRef-File-{i}", "fileName": name,
                       "checksums": [{"algorithm": "SHA256", "checksumValue": record["sha256"]}],
                       "licenseConcluded": "NOASSERTION", "licenseInfoInFiles": ["NOASSERTION"], "copyrightText": "NOASSERTION"}
                      for i, (name, record) in enumerate(sorted(files.items())) if "sha256" in record]}
    Path(str(asset) + ".spdx.json").write_text(json.dumps(sbom, indent=2) + "\n")


def verify(asset):
    manifest = json.loads(Path(str(asset) + ".manifest.json").read_text())
    if manifest["archive"] != asset.name or manifest["sha256"] != file_sha(asset):
        raise ValueError("Manifest archive digest/name mismatch")
    files, build = inventory(asset)
    if files != manifest["files"] or build != manifest["build"]:
        raise ValueError("Manifest does not describe the actual archive")
    sbom = json.loads(Path(str(asset) + ".spdx.json").read_text())
    actual_files = {f["fileName"]: f["checksums"][0]["checksumValue"] for f in sbom["files"]}
    if actual_files != {name: record["sha256"] for name, record in files.items() if "sha256" in record}:
        raise ValueError("SBOM file inventory mismatch")
    print(f"Verified manifest and SBOM: {asset.name}")


if __name__ == "__main__":
    {"generate": generate, "verify": verify}[sys.argv[1]](Path(sys.argv[2]))
