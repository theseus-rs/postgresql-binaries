#!/usr/bin/env python3
"""Check archive paths and links for portability before extracting a bundle."""

import sys
import tarfile
import zipfile

from archive_validation import verify_archive


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
