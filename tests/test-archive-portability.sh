#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -eq 0 ]; then
    # The normal regression suite covers every supported PostgreSQL major.
    # An explicit project version also covers older or future archive names.
    for major in 14 15 16 17 18; do
        bash "$root/tests/test-archive-portability.sh" "$major.0.0"
    done
    exit 0
fi
version="$1"
if [[ "$#" -ne 1 || ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Usage: test-archive-portability.sh [<major.minor.release>]' >&2
    exit 1
fi
source "$root/scripts/runtime-common.sh"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
archive="postgresql-$version-x86_64-unknown-linux-gnu"
echo "Testing archive portability for PostgreSQL $version"
source_stdlib="$temporary/source"
mkdir -p "$source_stdlib/encodings" "$source_stdlib/__pycache__" "$source_stdlib/site-packages"
printf 'standard library fixture\n' > "$source_stdlib/os.py"
printf 'encoding fixture\n' > "$source_stdlib/encodings/__init__.py"
printf 'third-party module\n' > "$source_stdlib/site-packages/extra.py"
for bytecode in sitecustomize.pyc sitecustomize.pyo __pycache__/sitecustomize.cpython-311.pyc; do
    printf 'host bytecode\n' > "$source_stdlib/$bytecode"
done
ln -s ../os.py "$source_stdlib/encodings/internal.py"
ln -s /etc/python3.11/sitecustomize.py "$source_stdlib/sitecustomize.py"

# Cover the reported host link (even when dangling), ordinary customization
# files and legacy bytecode. Test the produced archive, not just the copy tree.
for customization in symlink file; do
    if [ "$customization" = file ]; then
        rm "$source_stdlib/sitecustomize.py"
        printf 'host customization\n' > "$source_stdlib/sitecustomize.py"
    fi
    destination="$temporary/$customization/$archive/lib/python3.11"
    runtime_copy_stdlib "$source_stdlib" "$destination"
    for excluded in sitecustomize.py sitecustomize.pyc sitecustomize.pyo __pycache__ site-packages; do
        test ! -e "$destination/$excluded"
        test ! -L "$destination/$excluded"
    done
    cmp "$source_stdlib/os.py" "$destination/os.py"
    cmp "$source_stdlib/encodings/__init__.py" "$destination/encodings/__init__.py"
    test "$(readlink "$destination/encodings/internal.py")" = ../os.py
    tar -C "$temporary/$customization" -czf "$temporary/$customization.tar.gz" "$archive"
    python3 "$root/scripts/verify-archive.py" "$temporary/$customization.tar.gz" "$archive"
done

python3 - "$root" "$temporary" "$archive" <<'PY'
import io
from pathlib import Path
import stat
import subprocess
import sys
import tarfile
import zipfile

repository, temporary, root = map(Path, sys.argv[1:])
root = str(root)
helper = repository / "scripts/verify-archive.py"


def write_archive(asset, entries):
    if asset.name.endswith(".tar.gz"):
        with tarfile.open(asset, "w:gz") as archive:
            for name, kind, target in entries:
                member = tarfile.TarInfo(name)
                member.type = {"file": tarfile.REGTYPE, "directory": tarfile.DIRTYPE,
                               "symlink": tarfile.SYMTYPE, "hardlink": tarfile.LNKTYPE}[kind]
                if kind in ("symlink", "hardlink"):
                    member.linkname = target
                content = b"fixture" if kind == "file" else b""
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
    else:
        with zipfile.ZipFile(asset, "w") as archive:
            for name, kind, target in entries:
                member = zipfile.ZipInfo(name + "/" if kind == "directory" else name)
                member.create_system = 3
                mode = {"file": stat.S_IFREG, "directory": stat.S_IFDIR,
                        "symlink": stat.S_IFLNK}[kind]
                member.external_attr = (mode | 0o755) << 16
                archive.writestr(member, target if kind == "symlink" else b"fixture")


def check(label, entries, expected_error=None, extensions=("tar.gz", "zip")):
    for extension in extensions:
        asset = temporary / f"{label}.{extension}"
        write_archive(asset, entries)
        result = subprocess.run([sys.executable, str(helper), str(asset), root],
                                capture_output=True, text=True)
        if expected_error is None:
            assert result.returncode == 0, (label, extension, result.stderr)
        else:
            assert result.returncode != 0, (label, extension, "unexpected success")
            assert expected_error in result.stderr, (label, extension, result.stderr)


base = [(root, "directory", ""), (f"{root}/lib", "directory", ""),
        (f"{root}/lib/python3.11", "directory", ""), (f"{root}/lib/os.py", "file", "")]
check("safe links", base + [
    (f"{root}/lib/python3.11/internal.py", "symlink", "../os.py"),
    (f"{root}/lib/chain.py", "symlink", "python3.11/internal.py"),
    (f"{root}/lib/alias", "symlink", "./python3.11"),
    (f"{root}/lib/through-alias.py", "symlink", "alias/../os.py"),
])
for label, target in (
    ("sitecustomize", "/etc/python3.11/sitecustomize.py"),
    ("relative-escape", "../../../outside"),
    ("windows-absolute", "C:/Windows/host.py"),
    ("windows-drive-relative", "C:host.py"),
    ("windows-unc", r"\\host\share\host.py"),
    ("windows-traversal", r"..\..\..\outside"),
):
    check(label, base + [(f"{root}/lib/python3.11/sitecustomize.py", "symlink", target)],
          "Unsafe archive link")

# Each link appears lexically contained, but following the directory alias
# before applying '..' escapes. Put the referencing member first as well.
check("chain-escape", base + [
    (f"{root}/lib/python3.11/escape", "symlink", "up/../../outside"),
    (f"{root}/lib/python3.11/up", "symlink", ".."),
], "Link escapes the archive root")
check("cycle", base + [(f"{root}/lib/a", "symlink", "b"),
                       (f"{root}/lib/b", "symlink", "a")], "Cyclic")
check("safe-hardlink", base + [(f"{root}/lib/hard.py", "hardlink", f"{root}/lib/os.py")],
      extensions=("tar.gz",))
for label, target in (("absolute", "/etc/host.py"), ("escape", "../outside"),
                      ("sibling", "other-bundle/file"), ("parent-relative", "os.py"),
                      ("empty-root", ".")):
    check(f"hardlink-{label}", base + [(f"{root}/lib/hard.py", "hardlink", target)],
          "Unsafe archive link", extensions=("tar.gz",))
for label, member in (("absolute-member", "/outside"), ("traversal-member", f"{root}/../outside"),
                      ("sibling-member", "other-bundle/file")):
    check(label, base + [(member, "file", "")], "path" if label == "absolute-member" else "outside")
check("linked-parent", base + [(f"{root}/alias", "symlink", "lib"),
                                (f"{root}/alias/file", "file", "")], "non-directory parent")
check("duplicate", base + [(f"./{root}/lib/os.py", "symlink", "python3.11")], "Duplicate")

for customization in ("symlink", "file"):
    with tarfile.open(temporary / f"{customization}.tar.gz") as archive:
        assert not any("sitecustomize" in member.name for member in archive)

print("Archive portability checks passed for tar and ZIP paths, symlinks and tar hardlinks")
PY

# Exercise the real entrypoint with a valid checksum and make sure rejection
# occurs before either extractor (and before Docker or PostgreSQL is needed).
mkdir "$temporary/bin"
for extractor in tar unzip; do
    cat > "$temporary/bin/$extractor" <<'SH'
#!/bin/sh
echo 'Extractor must not run for an unsafe archive' >&2
touch "$EXTRACTOR_MARKER"
exit 99
SH
    chmod +x "$temporary/bin/$extractor"
done
for extension in tar.gz zip; do
    asset="$temporary/sitecustomize.$extension"
    "$root/scripts/checksum.sh" "$asset" > "$asset.sha256"
    if PATH="$temporary/bin:$PATH" EXTRACTOR_MARKER="$temporary/extracted" \
        TARGET=x86_64-unknown-linux-gnu bash "$root/scripts/test-archive.sh" "$asset" "$version" \
        > "$temporary/failure.log" 2>&1; then
        echo 'Unexpected success testing an unsafe archive' >&2
        exit 1
    fi
    grep -q 'Unsafe archive link' "$temporary/failure.log"
    test ! -e "$temporary/extracted"
done
echo 'Unsafe archives are rejected before extraction by the archive test entrypoint'
