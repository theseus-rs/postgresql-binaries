#!/usr/bin/env python3
"""Check archive paths and links for portability before extracting a bundle."""

from collections import deque
import ntpath
import stat
import sys
import tarfile
import zipfile


def archive_members(asset):
    if asset.endswith(".tar.gz"):
        with tarfile.open(asset, "r:gz") as archive:
            for member in archive:
                if member.issym():
                    kind = "symlink"
                elif member.islnk():
                    kind = "hardlink"
                elif member.isdir():
                    kind = "directory"
                elif member.isfile():
                    kind = "file"
                else:
                    raise ValueError(f"Unsupported archive member: {member.name!r}")
                yield member.name, kind, member.linkname
    elif asset.endswith(".zip"):
        with zipfile.ZipFile(asset) as archive:
            for member in archive.infolist():
                target = ""
                if stat.S_ISLNK(member.external_attr >> 16):
                    kind = "symlink"
                    target = archive.read(member).decode("utf-8")
                else:
                    kind = "directory" if member.is_dir() else "file"
                yield member.filename, kind, target
    else:
        raise ValueError(f"Unsupported archive format: {asset!r}")


def relative_parts(value):
    # Archive paths use POSIX separators even when extracted on Windows.
    # Reject drive paths and backslashes as well as POSIX absolute paths.
    if (not value or value.startswith("/") or "\\" in value
            or ntpath.splitdrive(value)[0] or "\0" in value):
        raise ValueError(f"Non-portable path: {value!r}")
    return tuple(part for part in value.split("/") if part not in ("", "."))


def verify_archive(asset, root):
    if relative_parts(root) != (root,) or root == "..":
        raise ValueError(f"Expected a single archive root directory: {root!r}")
    members = {}
    for name, kind, target in archive_members(asset):
        parts = relative_parts(name)
        if not parts or parts[0] != root or ".." in parts:
            raise ValueError(f"Archive member outside {root!r}: {name!r}")
        if parts in members:
            raise ValueError(f"Duplicate archive member: {name!r}")
        if parts == (root,) and kind != "directory":
            raise ValueError(f"Archive root is not a directory: {name!r}")
        if kind in ("symlink", "hardlink"):
            try:
                relative_parts(target)
            except ValueError as error:
                raise ValueError(f"Unsafe archive link {name!r} -> {target!r}: {error}") from error
        members[parts] = (kind, target)
    if not members:
        raise ValueError("Archive is empty")

    def resolve(parts):
        pending = deque(parts)
        resolved = []
        links = 0
        while pending:
            part = pending.popleft()
            if part == "..":
                if len(resolved) <= 1:
                    raise ValueError("Link escapes the archive root")
                resolved.pop()
                continue
            resolved.append(part)
            if resolved[0] != root:
                raise ValueError("Link escapes the archive root")
            kind, target = members.get(tuple(resolved), ("directory", ""))
            if kind in ("symlink", "hardlink"):
                links += 1
                if links > 40:
                    raise ValueError("Cyclic or excessively deep archive link")
                # Symlink targets are relative to their parent; tar hardlink
                # targets are relative to the start of the archive.
                if kind == "symlink":
                    resolved.pop()
                else:
                    resolved.clear()
                pending.extendleft(reversed(relative_parts(target)))
            elif kind != "directory" and pending:
                raise ValueError("Link traverses a non-directory member")
        if not resolved:
            raise ValueError("Link escapes the archive root")

    for parts, (kind, target) in members.items():
        name = "/".join(parts)
        # A tar writer does not descend into symlinks. Reject ambiguous layouts
        # whose extraction would depend on member order or overwrite a link.
        for length in range(1, len(parts)):
            parent = members.get(parts[:length])
            if parent is not None and parent[0] != "directory":
                raise ValueError(f"Archive member has a non-directory parent: {name!r}")
        if kind in ("symlink", "hardlink"):
            try:
                resolve(parts)
            except ValueError as error:
                raise ValueError(f"Unsafe archive link {name!r} -> {target!r}: {error}") from error


def main():
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} <archive> <root-directory>")
    try:
        verify_archive(sys.argv[1], sys.argv[2])
    except (ValueError, OSError, tarfile.TarError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error)) from error
    print(f"Archive paths and links are portable: {sys.argv[1]}")


if __name__ == "__main__":
    main()
